//! Repairing arbitrary file names into portable manifest paths, for
//! `repair_paths` on manifest build (V2-1771).
//!
//! A caller holding user-chosen names (Indelible's collection export) can't
//! hand them to a build as they are: ADR-0006 rejects any path that isn't
//! portable to every platform. Every rule here is ant-core's:
//! `portable_component` reduces one name, `fold` is the key two paths
//! collide under, and `validate_path` has the last word. So a repaired path
//! is exactly what `ant manifest download` accepts, and a repin picks up any
//! change to the rules. antd adds only the plumbing: splitting on `/`,
//! keeping a path inside the length limits, and suffixing collisions.

use std::collections::{HashMap, HashSet};

use ant_core::data::manifest::path::{
    fold, portable_component, validate_path, MAX_PATH_BYTES, MAX_PATH_COMPONENT_BYTES,
    PATH_SEPARATOR,
};

/// What a component, or a whole path, becomes when nothing usable is left.
const PLACEHOLDER: &str = "_";

/// A repaired path, split into its directories and its file name.
struct Base {
    /// The directories, joined with `/`; empty at the root.
    dir: String,
    file: String,
}

impl Base {
    fn path_with(&self, file: &str) -> String {
        if self.dir.is_empty() {
            file.to_string()
        } else {
            format!("{}{PATH_SEPARATOR}{file}", self.dir)
        }
    }

    /// Bytes the file name may take: the component limit, or what the whole
    /// path limit leaves after the directories, whichever is smaller.
    fn file_room(&self) -> usize {
        let dir = if self.dir.is_empty() {
            0
        } else {
            self.dir.len() + PATH_SEPARATOR.len_utf8()
        };
        MAX_PATH_COMPONENT_BYTES.min(MAX_PATH_BYTES.saturating_sub(dir))
    }
}

/// Repair one build's entry paths, in input order. An entry with no path
/// stays without one and takes no part in the collision handling.
///
/// Each path is repaired on its own first: it is split on `/`, empty, `.`
/// and `..` components are dropped, and every other component goes through
/// ant-core's `portable_component`, becoming `_` when nothing usable is left.
/// A path longer than the limit has its file name's stem shortened, keeping
/// the extension. Then collisions under ant-core's `fold` are resolved:
///
/// * every distinct path is kept as it is, so a later duplicate can never
///   take a name an entry already had;
/// * a duplicate, or a file whose path is also another entry's directory,
///   gets ` (2)`, ` (3)` and so on before its extension: the lowest number
///   that is free. Directories are never renamed.
///
/// The result depends only on the input, and every path it returns passes
/// ant-core's `validate_path` and `check_collisions`. On failure, each
/// entry that could not be repaired is returned as `(index, reason)`.
pub fn repair_paths(paths: &[Option<&str>]) -> Result<Vec<Option<String>>, Vec<(usize, String)>> {
    let mut bases = Vec::with_capacity(paths.len());
    let mut errors = Vec::new();
    for (i, path) in paths.iter().enumerate() {
        match path.map(repair_one).transpose() {
            Ok(base) => bases.push(base),
            Err(e) => {
                errors.push((i, e));
                bases.push(None);
            }
        }
    }
    if !errors.is_empty() {
        return Err(errors);
    }

    // Every directory the paths imply. A file may not take one of these
    // names: extraction would need it as a file and a directory at once.
    let dirs: HashSet<String> = bases
        .iter()
        .flatten()
        .flat_map(|base| directory_prefixes(&base.dir))
        .map(fold)
        .collect();

    let mut taken = HashSet::new();
    let mut repaired: Vec<Option<String>> = vec![None; bases.len()];
    let mut clashes = Vec::new();
    for (i, base) in bases.iter().enumerate() {
        let Some(base) = base else { continue };
        let path = base.path_with(&base.file);
        let key = fold(&path);
        if !dirs.contains(&key) && taken.insert(key) {
            repaired[i] = Some(path);
        } else {
            clashes.push(i);
        }
    }
    // Where the search for a free number starts, per clashing path: past
    // the last number given to that path, so N copies of one name cost N
    // tries rather than N².
    let mut next_number: HashMap<String, usize> = HashMap::new();
    for i in clashes {
        let Some(base) = &bases[i] else { continue };
        let room = base.file_room();
        let start = next_number
            .get(&fold(&base.path_with(&base.file)))
            .copied()
            .unwrap_or(2);
        // Each number gives a different name, so after at most this many
        // tries one is neither taken nor a directory.
        let tries = taken.len() + dirs.len() + 1;
        let free = (start..)
            .take(tries)
            .filter_map(|n| Some((n, fit_file(&base.file, &format!(" ({n})"), room)?)))
            .map(|(n, file)| (n, base.path_with(&file)))
            .find(|(_, path)| {
                let key = fold(path);
                !dirs.contains(&key) && taken.insert(key)
            });
        match free {
            Some((n, path)) => {
                next_number.insert(fold(&base.path_with(&base.file)), n + 1);
                repaired[i] = Some(path);
            }
            None => errors.push((i, "no free name is left for this path".to_string())),
        }
    }
    for (i, path) in repaired.iter().enumerate() {
        if let Some(Err(reason)) = path.as_deref().map(validate_path) {
            errors.push((i, format!("repair produced an invalid path: {reason}")));
        }
    }
    if errors.is_empty() {
        Ok(repaired)
    } else {
        errors.sort_by_key(|(i, _)| *i);
        Err(errors)
    }
}

/// Repair one path on its own, ignoring the other entries.
fn repair_one(path: &str) -> Result<Base, String> {
    let mut components: Vec<&str> = path
        .split(PATH_SEPARATOR)
        .filter(|c| !c.is_empty() && *c != "." && *c != "..")
        .collect();
    let file = components.pop();
    let dir = components
        .into_iter()
        .map(|c| portable_component(c).unwrap_or_else(|| PLACEHOLDER.to_string()))
        .collect::<Vec<_>>()
        .join(&PATH_SEPARATOR.to_string());
    let mut base = Base {
        dir,
        file: String::new(),
    };
    let room = base.file_room();
    // The file name is fitted from the name as given, so a cut shortens its
    // stem and keeps its extension.
    base.file = file
        .and_then(|name| fit_file(name, "", room))
        .or_else(|| (PLACEHOLDER.len() <= room).then(|| PLACEHOLDER.to_string()))
        .ok_or_else(|| {
            format!("its directories alone come to more than the {MAX_PATH_BYTES}-byte path limit")
        })?;
    Ok(base)
}

/// `name` with `suffix` put before its extension, in at most `max` bytes,
/// as a valid portable component. Only the stem is shortened; the
/// extension stays unless it would leave no room for any of the stem.
/// `None` when nothing fits.
fn fit_file(name: &str, suffix: &str, max: usize) -> Option<String> {
    let (stem, extension) = match name.rfind('.') {
        Some(dot) if dot > 0 && name.len() - dot + suffix.len() < max => name.split_at(dot),
        _ => (name, ""),
    };
    let mut keep = max
        .checked_sub(suffix.len() + extension.len())?
        .min(stem.len());
    loop {
        while !stem.is_char_boundary(keep) {
            keep -= 1;
        }
        // `portable_component` drops a trailing space or dot the cut left,
        // and prefixes a reserved name the cut produced.
        let candidate = portable_component(&format!("{}{suffix}{extension}", &stem[..keep]));
        if let Some(candidate) = candidate.filter(|c| c.len() <= max) {
            return Some(candidate);
        }
        keep = keep.checked_sub(1)?;
    }
}

/// `a/b/c` → `a`, `a/b`, `a/b/c`. Nothing for the root.
fn directory_prefixes(dir: &str) -> impl Iterator<Item = &str> {
    dir.match_indices(PATH_SEPARATOR)
        .map(move |(end, _)| &dir[..end])
        .chain((!dir.is_empty()).then_some(dir))
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::*;
    use ant_core::data::manifest::path::check_collisions;

    fn repair(paths: &[&str]) -> Vec<String> {
        let input: Vec<Option<&str>> = paths.iter().map(|p| Some(*p)).collect();
        let out: Vec<String> = repair_paths(&input)
            .expect("repairs")
            .into_iter()
            .map(|p| p.expect("a path in, a path out"))
            .collect();
        assert_valid_set(&out);
        out
    }

    /// Every path valid on its own, and no two colliding as ant-core sees it.
    fn assert_valid_set(paths: &[String]) {
        for p in paths {
            assert_eq!(validate_path(p), Ok(()), "{p:?}");
        }
        assert_eq!(
            check_collisions(paths.iter().map(String::as_str)),
            Ok(()),
            "{paths:?}"
        );
    }

    #[test]
    fn portable_paths_are_left_alone() {
        let paths = [
            "a.txt",
            "My Report 2026.pdf",
            " leading space.txt",
            "docs/notes/ñandú (draft).md",
            ".hidden",
        ];
        assert_eq!(repair(&paths), paths);
    }

    #[test]
    fn forbidden_characters_become_underscores() {
        assert_eq!(
            repair(&["a:b?.txt", "q/\"quoted\" <tag>|*.md", "back\\slash.txt"]),
            ["a_b_.txt", "q/_quoted_ _tag___.md", "back_slash.txt"]
        );
    }

    #[test]
    fn control_characters_become_underscores() {
        assert_eq!(
            repair(&["tab\there.txt", "del\u{7f}.txt"]),
            ["tab_here.txt", "del_.txt"]
        );
    }

    #[test]
    fn trailing_spaces_and_dots_are_dropped_from_every_component() {
        assert_eq!(
            repair(&["report.", "drafts /notes . /x.txt  "]),
            ["report", "drafts/notes/x.txt"]
        );
    }

    #[test]
    fn reserved_device_names_gain_a_prefix() {
        assert_eq!(
            repair(&["CON.txt", "aux/readme", "lpt1 .log"]),
            ["_CON.txt", "_aux/readme", "_lpt1 .log"]
        );
    }

    #[test]
    fn empty_dot_and_dotdot_components_are_dropped() {
        assert_eq!(repair(&["/a//./../b.txt"]), ["a/b.txt"]);
    }

    #[test]
    fn a_component_with_nothing_usable_becomes_an_underscore() {
        assert_eq!(repair(&["...", "a/ . /b", "/"]), ["_", "a/_/b", "_ (2)"]);
    }

    #[test]
    fn entries_without_a_path_stay_without_one() {
        let out = repair_paths(&[None, Some("a:b"), None]).unwrap();
        assert_eq!(out, [None, Some("a_b".to_string()), None]);
    }

    #[test]
    fn case_collisions_get_a_numbered_suffix_before_the_extension() {
        assert_eq!(
            repair(&["Readme.md", "README.md", "readme.md"]),
            ["Readme.md", "README (2).md", "readme (3).md"]
        );
    }

    #[test]
    fn unicode_folding_collisions_are_caught() {
        // ß folds to ss, so the two directories are one on APFS and NTFS.
        assert_eq!(
            repair(&["Straße/x.txt", "STRASSE/x.txt"]),
            ["Straße/x.txt", "STRASSE/x (2).txt"]
        );
    }

    #[test]
    fn a_name_already_given_is_never_taken_by_a_suffix() {
        // `a (2).txt` is a real entry, so the duplicate of `a.txt` skips it.
        assert_eq!(
            repair(&["a.txt", "A.txt", "a (2).txt"]),
            ["a.txt", "A (3).txt", "a (2).txt"]
        );
    }

    #[test]
    fn repaired_names_collide_like_any_other() {
        assert_eq!(repair(&["a:b.txt", "a?b.txt"]), ["a_b.txt", "a_b (2).txt"]);
    }

    #[test]
    fn a_file_named_like_a_directory_is_renamed_not_the_directory() {
        assert_eq!(
            repair(&["docs", "docs/readme.md", "Docs/sub/x"]),
            ["docs (2)", "docs/readme.md", "Docs/sub/x"]
        );
        // The file may come after the directory, and match it only by case.
        assert_eq!(
            repair(&["Photos/a.jpg", "photos"]),
            ["Photos/a.jpg", "photos (2)"]
        );
    }

    #[test]
    fn dotfiles_take_the_suffix_at_the_end() {
        assert_eq!(repair(&[".bashrc", ".BASHRC"]), [".bashrc", ".BASHRC (2)"]);
    }

    #[test]
    fn long_names_are_cut_in_the_stem_keeping_the_extension() {
        let long = format!("{}.pdf", "x".repeat(300));
        let out = repair(&[&long]);
        assert_eq!(out[0].len(), MAX_PATH_COMPONENT_BYTES);
        assert!(out[0].ends_with(".pdf"), "{}", out[0]);
    }

    #[test]
    fn a_suffix_on_a_full_length_name_shortens_the_stem() {
        let long = format!("{}.pdf", "y".repeat(251));
        assert_eq!(long.len(), MAX_PATH_COMPONENT_BYTES);
        let out = repair(&[&long, &long.to_uppercase()]);
        assert_eq!(out[0], long);
        assert_eq!(out[1].len(), MAX_PATH_COMPONENT_BYTES);
        assert!(out[1].ends_with(" (2).PDF"), "{}", out[1]);
    }

    #[test]
    fn cuts_never_split_a_character() {
        let long = format!("{}.txt", "é".repeat(200)); // 2 bytes each
        let out = repair(&[&long, &long]);
        assert!(out[0].len() <= MAX_PATH_COMPONENT_BYTES);
        assert!(out[1].ends_with(" (2).txt"), "{}", out[1]);
    }

    #[test]
    fn a_long_path_shortens_its_file_name_to_fit() {
        let dirs = vec!["d".repeat(200); 4].join("/"); // 803 bytes
        let path = format!("{dirs}/{}.bin", "f".repeat(250));
        let out = repair(&[&path]);
        assert!(out[0].len() <= MAX_PATH_BYTES, "{}", out[0].len());
        assert!(out[0].starts_with(&dirs) && out[0].ends_with(".bin"));
    }

    #[test]
    fn directories_alone_over_the_limit_fail_that_entry_only() {
        let deep = format!("{}/x.txt", vec!["d".repeat(250); 5].join("/"));
        let errors = repair_paths(&[Some("fine.txt"), Some(&deep)]).unwrap_err();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].0, 1);
        assert!(errors[0].1.contains("path limit"), "{}", errors[0].1);
    }

    #[test]
    fn many_duplicates_all_get_distinct_names() {
        let paths = vec!["same.txt"; 50];
        let out = repair(&paths);
        assert_eq!(out[0], "same.txt");
        assert_eq!(out[49], "same (50).txt");
    }

    #[test]
    fn many_copies_of_one_name_cost_linear_time() {
        // Quadratic search would take minutes here; this runs in well under
        // a second.
        let paths = vec!["same.txt"; 20_000];
        let input: Vec<Option<&str>> = paths.iter().map(|p| Some(*p)).collect();
        let out = repair_paths(&input).unwrap();
        assert_eq!(out[19_999].as_deref(), Some("same (20000).txt"));
    }

    #[test]
    fn a_long_name_keeps_its_extension_even_with_forbidden_characters() {
        let long = format!("{}:x.pdf", "z".repeat(300));
        let out = repair(&[&long]);
        assert_eq!(out[0].len(), MAX_PATH_COMPONENT_BYTES);
        assert!(out[0].ends_with(".pdf"), "{}", out[0]);
    }

    #[test]
    fn repair_is_deterministic() {
        let paths = ["b/C.txt", "B/c.txt", "a:x", "CON", "con.txt", "b"];
        assert_eq!(repair(&paths), repair(&paths));
    }

    #[test]
    fn a_mix_of_hostile_names_always_yields_a_valid_set() {
        let names = [
            "",
            "/",
            ".",
            "..",
            "...",
            " ",
            "CON",
            "con.txt",
            "a:b",
            "A:B",
            "x.",
            "x",
            "X",
            "x/",
            "x/y",
            "X/Y.",
            "nul .txt",
            "\u{1}",
            "ß",
            "SS",
            "ss/ß",
            "tab\t",
            "photos",
            "Photos/1.jpg",
            "photos (2)",
            "a/../b",
            "./c",
            "c",
        ];
        let input: Vec<Option<&str>> = names.iter().map(|n| Some(*n)).collect();
        let out: Vec<String> = repair_paths(&input)
            .unwrap()
            .into_iter()
            .map(Option::unwrap)
            .collect();
        assert_eq!(out.len(), names.len());
        assert_valid_set(&out);
    }
}
