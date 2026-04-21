//! Bootstrap peer resolution helpers.

use std::net::SocketAddr;

use ant_core::data::MultiAddr;

/// Convert a [`SocketAddr`] (as read from ant-client's `bootstrap_peers.toml`)
/// into the libp2p-style `/ip4/<ip>/udp/<port>/quic` multiaddr string that
/// saorsa-core expects, then parse it into a [`MultiAddr`].
///
/// Returns `None` if the result does not parse — callers log and skip.
pub fn socket_addr_to_multiaddr(addr: &SocketAddr) -> Option<MultiAddr> {
    let ip_tag = if addr.is_ipv4() { "ip4" } else { "ip6" };
    format!("/{}/{}/udp/{}/quic", ip_tag, addr.ip(), addr.port())
        .parse()
        .ok()
}

/// Best-effort fallback: load peers from ant-client's shared
/// `bootstrap_peers.toml` and convert them to MultiAddrs. Returns an empty
/// vector on any failure — the caller decides whether to warn.
///
/// Returns `(peers, source_path)` for logging. `source_path` is `None` when
/// the fallback file does not exist.
pub fn load_from_ant_client_config() -> (Vec<MultiAddr>, Option<std::path::PathBuf>) {
    let path = ant_core::config::config_dir()
        .ok()
        .map(|d| d.join("bootstrap_peers.toml"));

    let socket_addrs = match ant_core::config::load_bootstrap_peers() {
        Ok(Some(addrs)) => addrs,
        Ok(None) => return (Vec::new(), None),
        Err(e) => {
            tracing::warn!(error = %e, "failed to read bootstrap_peers.toml fallback");
            return (Vec::new(), path);
        }
    };

    let peers: Vec<MultiAddr> = socket_addrs
        .iter()
        .filter_map(socket_addr_to_multiaddr)
        .collect();

    (peers, path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{Ipv4Addr, Ipv6Addr, SocketAddrV4, SocketAddrV6};

    #[test]
    fn ipv4_socket_addr_produces_ip4_quic_multiaddr() {
        let sa = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(127, 0, 0, 1), 10000));
        let ma = socket_addr_to_multiaddr(&sa).expect("should parse");
        // round-trip through Display
        let as_str = format!("{ma}");
        assert!(
            as_str.contains("/ip4/127.0.0.1") && as_str.contains("10000"),
            "unexpected multiaddr: {as_str}"
        );
    }

    #[test]
    fn ipv6_socket_addr_produces_ip6_quic_multiaddr() {
        let sa = SocketAddr::V6(SocketAddrV6::new(Ipv6Addr::LOCALHOST, 20000, 0, 0));
        let ma = socket_addr_to_multiaddr(&sa).expect("should parse");
        let as_str = format!("{ma}");
        assert!(
            as_str.contains("/ip6/") && as_str.contains("20000"),
            "unexpected multiaddr: {as_str}"
        );
    }
}
