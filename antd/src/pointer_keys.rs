//! Pointer owner keys, loaded once at startup.
//!
//! A pointer's owner key signs every state the pointer takes, and it can never
//! change: the pointer's address is derived from it. antd holds these keys the
//! way it holds the EVM wallet key. The operator supplies them once, through
//! `--pointer-keys`; antd never logs, persists or returns them; and no request
//! carries one. A write names the pointer by its address, and antd signs with
//! the key it loaded for that address.
//!
//! A key file is what `ant pointer keygen` writes: the 32-byte FIPS 204 seed
//! the ML-DSA-65 key pair derives from, hex-encoded on one line. A file made by
//! the `ant` CLI loads here unchanged, and the reverse.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use ant_core::data::{ml_dsa_65, pointer_address, MlDsaPublicKey, MlDsaSecretKey, XorName};
use tokio::sync::Mutex;
use zeroize::Zeroizing;

/// Length of an owner key seed in bytes.
const SEED_LEN: usize = 32;

/// One pointer's owner key pair.
pub struct PointerKey {
    pub public: MlDsaPublicKey,
    pub secret: MlDsaSecretKey,
    /// Serialises this daemon's writes to the pointer. Two writes signed
    /// against the same served counter are both paid for, and only one of the
    /// states survives the merge, so the second payment buys nothing.
    pub write_lock: Mutex<()>,
}

/// The owner keys this daemon can sign with, by pointer address.
#[derive(Default)]
pub struct PointerKeys {
    keys: BTreeMap<XorName, PointerKey>,
}

impl std::fmt::Debug for PointerKeys {
    /// Says how many keys there are and nothing about them.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PointerKeys")
            .field("count", &self.keys.len())
            .finish_non_exhaustive()
    }
}

impl PointerKeys {
    /// Load the key at `path`, or every key in it if it is a directory.
    ///
    /// In a directory every regular file is a key except hidden ones (a name
    /// starting with `.`). Any file that is not a key fails the load rather
    /// than being skipped: a key that is silently missing would surface later
    /// as a write that cannot be signed. So does an empty directory, and two
    /// files holding the same key.
    ///
    /// Errors name the file, never its contents.
    pub fn load(path: &Path) -> Result<Self, String> {
        let meta = std::fs::metadata(path)
            .map_err(|e| format!("cannot read pointer keys at {}: {e}", path.display()))?;
        let files = if meta.is_dir() {
            key_files_in(path)?
        } else {
            vec![path.to_path_buf()]
        };
        if files.is_empty() {
            return Err(format!(
                "no pointer key files in {} (create one with `ant pointer keygen`)",
                path.display()
            ));
        }

        let mut keys = BTreeMap::new();
        let mut sources: BTreeMap<XorName, PathBuf> = BTreeMap::new();
        for file in files {
            let (address, key) = read_key_file(&file)?;
            if let Some(first) = sources.get(&address) {
                return Err(format!(
                    "{} and {} hold the same key (pointer {})",
                    first.display(),
                    file.display(),
                    hex::encode(address)
                ));
            }
            warn_if_shared(&file);
            sources.insert(address, file);
            keys.insert(address, key);
        }
        Ok(Self { keys })
    }

    /// The key that owns the pointer at `address`, if it is loaded.
    pub fn get(&self, address: &XorName) -> Option<&PointerKey> {
        self.keys.get(address)
    }

    /// The addresses of every loaded key's pointer, in ascending order.
    pub fn addresses(&self) -> impl Iterator<Item = &XorName> {
        self.keys.keys()
    }

    pub fn len(&self) -> usize {
        self.keys.len()
    }

    pub fn is_empty(&self) -> bool {
        self.keys.is_empty()
    }
}

/// The regular, non-hidden files directly inside `dir`, sorted by name.
fn key_files_in(dir: &Path) -> Result<Vec<PathBuf>, String> {
    let entries = std::fs::read_dir(dir)
        .map_err(|e| format!("cannot list pointer keys in {}: {e}", dir.display()))?;
    let mut files = Vec::new();
    for entry in entries {
        let entry =
            entry.map_err(|e| format!("cannot list pointer keys in {}: {e}", dir.display()))?;
        if entry.file_name().to_string_lossy().starts_with('.') {
            continue;
        }
        let path = entry.path();
        // Follows symlinks, so a key linked in from elsewhere counts.
        if path.is_file() {
            files.push(path);
        }
    }
    files.sort();
    Ok(files)
}

/// Read one key file into the address it owns and its key pair.
fn read_key_file(path: &Path) -> Result<(XorName, PointerKey), String> {
    let display = path.display();
    let text = Zeroizing::new(
        std::fs::read_to_string(path)
            .map_err(|e| format!("cannot read pointer key file {display}: {e}"))?,
    );
    // hex's own error quotes the offending character; this one does not.
    let bytes = Zeroizing::new(
        hex::decode(text.trim())
            .map_err(|_| format!("pointer key file {display} is not a hex-encoded key"))?,
    );
    if bytes.len() != SEED_LEN {
        return Err(format!(
            "pointer key file {display} holds {} bytes, expected a {SEED_LEN}-byte seed",
            bytes.len()
        ));
    }
    let mut seed = Zeroizing::new([0u8; SEED_LEN]);
    seed.copy_from_slice(&bytes);
    let (public, secret) = ml_dsa_65().generate_keypair_from_seed(&seed);
    let address = pointer_address(&public);
    Ok((
        address,
        PointerKey {
            public,
            secret,
            write_lock: Mutex::new(()),
        },
    ))
}

/// Warn when a key file can be read by anyone but its owner. `ant pointer
/// keygen` creates them `0600`.
#[cfg(unix)]
fn warn_if_shared(path: &Path) {
    use std::os::unix::fs::PermissionsExt as _;
    if let Ok(meta) = std::fs::metadata(path) {
        let mode = meta.permissions().mode() & 0o777;
        if mode & 0o077 != 0 {
            tracing::warn!(
                path = %path.display(),
                mode = format!("{mode:o}"),
                "pointer key file is readable by other users; restrict it with chmod 600"
            );
        }
    }
}

#[cfg(not(unix))]
fn warn_if_shared(_path: &Path) {}

#[cfg(test)]
mod tests {
    use super::*;

    fn address_of(seed: [u8; SEED_LEN]) -> XorName {
        let (public, _) = ml_dsa_65().generate_keypair_from_seed(&seed);
        pointer_address(&public)
    }

    /// Writes a key file the way `ant pointer keygen` does: hex and a newline.
    fn write_key(dir: &Path, name: &str, seed: [u8; SEED_LEN]) -> PathBuf {
        let path = dir.join(name);
        std::fs::write(&path, format!("{}\n", hex::encode(seed))).unwrap();
        path
    }

    #[test]
    fn a_single_key_file_loads_to_the_pointer_it_owns() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_key(dir.path(), "owner.key", [7; SEED_LEN]);

        let keys = PointerKeys::load(&path).unwrap();

        assert_eq!(keys.len(), 1);
        let address = address_of([7; SEED_LEN]);
        assert_eq!(keys.addresses().collect::<Vec<_>>(), vec![&address]);
        let key = keys.get(&address).unwrap();
        assert_eq!(pointer_address(&key.public), address);
    }

    #[test]
    fn a_directory_loads_every_key_and_skips_hidden_files() {
        let dir = tempfile::tempdir().unwrap();
        write_key(dir.path(), "a.key", [1; SEED_LEN]);
        write_key(dir.path(), "b.key", [2; SEED_LEN]);
        std::fs::write(dir.path().join(".DS_Store"), "not a key").unwrap();
        std::fs::create_dir(dir.path().join("archive")).unwrap();

        let keys = PointerKeys::load(dir.path()).unwrap();

        assert_eq!(keys.len(), 2);
        assert!(keys.get(&address_of([1; SEED_LEN])).is_some());
        assert!(keys.get(&address_of([2; SEED_LEN])).is_some());
        assert!(keys.get(&address_of([3; SEED_LEN])).is_none());
    }

    #[test]
    fn surrounding_whitespace_is_ignored() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("owner.key");
        std::fs::write(&path, format!("  {}\r\n\n", hex::encode([9; SEED_LEN]))).unwrap();

        let keys = PointerKeys::load(&path).unwrap();

        assert!(keys.get(&address_of([9; SEED_LEN])).is_some());
    }

    #[test]
    fn a_file_that_is_not_a_key_fails_the_load_without_quoting_it() {
        let dir = tempfile::tempdir().unwrap();
        write_key(dir.path(), "good.key", [1; SEED_LEN]);
        std::fs::write(dir.path().join("notes.txt"), "secret-looking-text").unwrap();

        let err = PointerKeys::load(dir.path()).unwrap_err();

        assert!(err.contains("notes.txt"), "{err}");
        assert!(!err.contains("secret-looking-text"), "{err}");
    }

    #[test]
    fn a_key_of_the_wrong_length_fails_the_load() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("short.key");
        std::fs::write(&path, hex::encode([1u8; 16])).unwrap();

        let err = PointerKeys::load(&path).unwrap_err();

        assert!(err.contains("holds 16 bytes"), "{err}");
        assert!(!err.contains(&hex::encode([1u8; 16])), "{err}");
    }

    #[test]
    fn two_files_holding_one_key_fail_the_load() {
        let dir = tempfile::tempdir().unwrap();
        write_key(dir.path(), "a.key", [4; SEED_LEN]);
        write_key(dir.path(), "copy.key", [4; SEED_LEN]);

        let err = PointerKeys::load(dir.path()).unwrap_err();

        assert!(err.contains("hold the same key"), "{err}");
        assert!(
            err.contains(&hex::encode(address_of([4; SEED_LEN]))),
            "{err}"
        );
    }

    #[test]
    fn an_empty_directory_fails_the_load() {
        let dir = tempfile::tempdir().unwrap();

        let err = PointerKeys::load(dir.path()).unwrap_err();

        assert!(err.contains("no pointer key files"), "{err}");
    }

    #[test]
    fn debug_output_shows_no_key_material() {
        let dir = tempfile::tempdir().unwrap();
        let path = write_key(dir.path(), "owner.key", [5; SEED_LEN]);
        let keys = PointerKeys::load(&path).unwrap();

        let shown = format!("{keys:?}");

        assert!(shown.contains("count: 1"), "{shown}");
        assert!(!shown.contains(&hex::encode([5; SEED_LEN])), "{shown}");
    }
}
