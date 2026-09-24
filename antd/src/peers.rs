//! Bootstrap peer resolution helpers.
//!
//! Two sources feed the daemon when no `--peers` / `ANTD_PEERS` were given:
//! the shared `bootstrap_peers.toml` that the `ant` CLI installer drops in the
//! platform config dir, and the seed list bundled into ant-core itself.
//!
//! Both go through ant-core's `network_defaults` parser, which accepts the two
//! on-disk shapes that have existed so far:
//!
//! * legacy (ant-cli <= 0.3.7): `peers = ["<ip>:<port>", ...]`
//! * current (ant-cli >= 0.3.8, ADR-0005): `quic = ["/ip4/<ip>/udp/<port>/quic[/p2p/<id>]", ...]`
//!   plus a `webrtc = [...]` list for browser clients.
//!
//! The parser validates the whole file, both lists, before handing back the
//! QUIC seeds: a malformed or duplicate entry in either list rejects the file
//! as a unit rather than skipping that entry. Valid WebRTC entries are
//! accepted and then simply not dialled by this native client. A rejected
//! on-disk file is logged with the path and the daemon continues with the
//! bundled seeds (on non-local networks), so a bad file degrades to
//! defaults instead of failing closed.
//!
//! `/p2p/<peer-id>` pins survive into the dialled [`MultiAddr`]. The daemon
//! used to carry its own copy of the file and its own `peers`-only parser;
//! that copy could not read the current shape and silently fell back to a
//! vendored list that drifts from upstream between pin bumps. Delegating to
//! ant-core removes both failure modes: the parser is the one the CLI uses,
//! and the bundled seeds are whatever the pinned ant-core ships.

use std::path::PathBuf;

use ant_core::data::MultiAddr;
use ant_core::network_defaults::{bundled_bootstrap_seeds, parse_bootstrap_seeds};

/// Parse the text of a `bootstrap_peers.toml` in either the legacy `peers`
/// shape or the current `quic`/`webrtc` shape and return the native QUIC
/// seeds, `/p2p/` pins included. The WebRTC list is validated with the rest
/// of the file (an invalid entry there is an error for the whole file) and
/// then not returned, since this client never dials WebRTC. Errors carry
/// ant-core's message.
pub fn parse_peers_file(text: &str) -> Result<Vec<MultiAddr>, String> {
    parse_bootstrap_seeds(text)
        .map(|seeds| seeds.quic)
        .map_err(|e| e.to_string())
}

/// Best-effort fallback: load peers from the shared `bootstrap_peers.toml`
/// in the platform config dir (`%APPDATA%/ant`, `~/.config/ant`,
/// `~/Library/Application Support/ant`). Returns an empty vector on any
/// failure — the caller decides whether to warn.
///
/// Returns `(peers, source_path)` for logging. `source_path` is `None` when
/// the config dir cannot be determined or the file does not exist.
pub fn load_from_ant_client_config() -> (Vec<MultiAddr>, Option<PathBuf>) {
    let Ok(dir) = ant_core::config::config_dir() else {
        return (Vec::new(), None);
    };
    let path = dir.join("bootstrap_peers.toml");
    if !path.exists() {
        return (Vec::new(), None);
    }
    let text = match std::fs::read_to_string(&path) {
        Ok(t) => t,
        Err(e) => {
            tracing::warn!(path = %path.display(), error = %e, "failed to read bootstrap_peers.toml fallback");
            return (Vec::new(), Some(path));
        }
    };
    match parse_peers_file(&text) {
        Ok(peers) => (peers, Some(path)),
        Err(e) => {
            tracing::warn!(path = %path.display(), error = %e, "failed to parse bootstrap_peers.toml fallback");
            (Vec::new(), Some(path))
        }
    }
}

/// Last-resort fallback: the mainnet seed list bundled into the pinned
/// ant-core (the same resource the `ant` CLI ships). Returns an empty vector
/// if that resource is malformed, which would be an upstream build regression.
pub fn bundled_default_peers() -> Vec<MultiAddr> {
    match bundled_bootstrap_seeds() {
        Ok(seeds) => seeds.quic,
        Err(e) => {
            tracing::warn!(error = %e, "ant-core's bundled bootstrap seeds failed to parse");
            Vec::new()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_peers_shape_yields_quic_multiaddrs() {
        // The file the ant-cli <= 0.3.7 installers wrote.
        let peers =
            parse_peers_file("peers = [\n    \"207.148.94.42:10000\",\n    \"[::1]:20000\",\n]\n")
                .expect("legacy shape must parse");
        let as_str: Vec<String> = peers.iter().map(|m| m.to_string()).collect();
        assert_eq!(
            as_str,
            [
                "/ip4/207.148.94.42/udp/10000/quic",
                "/ip6/::1/udp/20000/quic"
            ]
        );
    }

    #[test]
    fn current_quic_shape_preserves_peer_pins_and_ignores_webrtc() {
        // The file ant-cli >= 0.3.8 installs (ADR-0005).
        let pin = "ab".repeat(32);
        let text = format!(
            "quic = [\n    \"/ip4/45.77.50.10/udp/10000/quic\",\n    \"/ip4/66.135.23.83/udp/10000/quic/p2p/{pin}\",\n]\nwebrtc = []\n"
        );
        let peers = parse_peers_file(&text).expect("current shape must parse");
        assert_eq!(peers.len(), 2);
        assert!(peers[0].peer_id().is_none());
        assert_eq!(
            peers[1].to_string(),
            format!("/ip4/66.135.23.83/udp/10000/quic/p2p/{pin}")
        );
        assert!(peers[1].peer_id().is_some(), "the /p2p/ pin must survive");
    }

    /// A syntactically valid WebRTC Direct seed as the browser SDK would
    /// publish it: certhash multihash (sha2-256, 0x12 0x20) base64url-encoded
    /// with the `u` multibase prefix, plus a peer pin.
    fn valid_webrtc_seed() -> String {
        use base64::Engine;
        let mut hash = vec![0x12, 0x20];
        hash.extend([0xbb; 32]);
        let cert = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(hash);
        format!(
            "/ip4/127.0.0.1/udp/24000/webrtc-direct/certhash/u{cert}/p2p/{}",
            "cd".repeat(32)
        )
    }

    #[test]
    fn valid_webrtc_entries_are_accepted_but_not_returned() {
        // Once mainnet WebRTC seeds are published the installed file will
        // carry them alongside the QUIC list; the native client must keep
        // reading such a file and dial only the QUIC seeds.
        let text = format!(
            "quic = [\"/ip4/45.77.50.10/udp/10000/quic\"]
webrtc = [\"{}\"]
",
            valid_webrtc_seed()
        );
        let peers = parse_peers_file(&text).expect("file with a valid WebRTC seed must parse");
        assert_eq!(peers.len(), 1, "only the QUIC seed is dialled");
        assert_eq!(peers[0].to_string(), "/ip4/45.77.50.10/udp/10000/quic");
    }

    #[test]
    fn malformed_webrtc_entry_rejects_the_whole_file() {
        // The shared parser validates both lists before returning either, so
        // a bad WebRTC entry is a file-level error even though this client
        // would never dial it. main.rs then warns and falls back to the
        // bundled seeds; the QUIC entries in the bad file are NOT salvaged.
        let quic_only = "quic = [\"/ip4/45.77.50.10/udp/10000/quic\"]
";
        assert!(parse_peers_file(quic_only).is_ok());
        for bad in [
            "webrtc = [\"/ip4/127.0.0.1/udp/10000/quic\"]", // wrong transport
            "webrtc = [\"127.0.0.1:24000\"]",               // bare socket
            "webrtc = [\"/ip4/127.0.0.1/udp/24000/webrtc-direct\"]", // no certhash / pin
        ] {
            let text = format!(
                "{quic_only}{bad}
"
            );
            assert!(parse_peers_file(&text).is_err(), "should reject: {bad}");
        }
        // Duplicates in the WebRTC list are also a file-level error.
        let dup = format!(
            "{quic_only}webrtc = [\"{0}\", \"{0}\"]
",
            valid_webrtc_seed()
        );
        assert!(
            parse_peers_file(&dup).is_err(),
            "duplicate WebRTC seed must reject the file"
        );
    }

    #[test]
    fn malformed_file_is_an_error_not_an_empty_list() {
        // A caller must be able to tell "no peers" from "could not read".
        assert!(parse_peers_file("quic = [\"not an address\"]").is_err());
        assert!(parse_peers_file("bootstrap = [\"127.0.0.1:10000\"]").is_err());
        assert!(parse_peers_file("this is not toml").is_err());
    }

    #[test]
    fn bundled_default_peers_are_non_empty_quic_multiaddrs() {
        let peers = bundled_default_peers();
        assert!(
            !peers.is_empty(),
            "ant-core's bundled bootstrap seeds produced zero peers"
        );
        for ma in &peers {
            assert!(ma.is_quic(), "unexpected multiaddr shape: {ma}");
            assert!(
                ma.socket_addr().is_some_and(|a| a.port() != 0),
                "seed without a usable socket address: {ma}"
            );
        }
    }
}
