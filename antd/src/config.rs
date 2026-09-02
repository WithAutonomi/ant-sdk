use clap::Parser;

#[derive(Parser, Debug, Clone)]
#[command(name = "antd", about = "REST + gRPC gateway for Autonomi network")]
pub struct Config {
    /// REST API listen address. Defaults to loopback only — pass
    /// `0.0.0.0:8082` (or a specific interface) to expose on the network.
    /// antd has no built-in auth, so opt in to external binding deliberately.
    #[arg(long, default_value = "127.0.0.1:8082", env = "ANTD_REST_ADDR")]
    pub rest_addr: String,

    /// gRPC listen address. Defaults to loopback only — pass
    /// `0.0.0.0:50051` (or a specific interface) to expose on the network.
    #[arg(long, default_value = "127.0.0.1:50051", env = "ANTD_GRPC_ADDR")]
    pub grpc_addr: String,

    /// REST API port (overrides --rest-addr port; use 0 for OS-assigned)
    #[arg(long, env = "ANTD_REST_PORT")]
    pub rest_port: Option<u16>,

    /// gRPC port (overrides --grpc-addr port; use 0 for OS-assigned)
    #[arg(long, env = "ANTD_GRPC_PORT")]
    pub grpc_port: Option<u16>,

    /// Network mode: default, local
    #[arg(long, default_value = "default", env = "ANTD_NETWORK")]
    pub network: String,

    /// Comma-separated bootstrap peer multiaddrs
    #[arg(long, env = "ANTD_PEERS", value_delimiter = ',')]
    pub peers: Option<Vec<String>>,

    /// Enable CORS for browser callers. Bare `--cors` allows browser-extension
    /// origins only. Pass a comma-separated list of origins to also allow
    /// specific web pages (e.g. `--cors http://127.0.0.1:8000`), or `*` to
    /// allow any origin (unsafe outside development: any webpage can then
    /// drive this daemon's REST API, including wallet endpoints).
    #[arg(long, env = "ANTD_CORS", value_name = "ORIGINS", num_args = 0..=1, default_missing_value = "true")]
    pub cors: Option<String>,

    /// Log level: trace, debug, info, warn, error
    #[arg(long, default_value = "info", env = "ANTD_LOG_LEVEL")]
    pub log_level: String,

    /// Timeout in seconds for lightweight network operations (quotes, DHT lookups).
    #[arg(long, env = "ANTD_QUOTE_TIMEOUT_SECS")]
    pub quote_timeout_secs: Option<u64>,

    /// Timeout in seconds for chunk store (PUT) operations. Should be higher
    /// than --quote-timeout-secs because each PUT transfers ~4MB to multiple peers.
    #[arg(long, env = "ANTD_STORE_TIMEOUT_SECS")]
    pub store_timeout_secs: Option<u64>,

    /// Maximum number of chunks quoted or downloaded concurrently (pure network I/O).
    #[arg(long, env = "ANTD_QUOTE_CONCURRENCY")]
    pub quote_concurrency: Option<usize>,

    /// Maximum number of chunks stored concurrently during uploads. Lower values
    /// reduce outbound bandwidth pressure on slow connections.
    #[arg(long, env = "ANTD_STORE_CONCURRENCY")]
    pub store_concurrency: Option<usize>,
}

/// Parsed CORS policy derived from `--cors` / `ANTD_CORS`.
///
/// Browser-extension origins (`chrome-extension://`, `moz-extension://`,
/// `safari-web-extension://`) are allowed in every enabled mode: extensions
/// can already bypass CORS entirely by requesting localhost host-permissions,
/// so echoing their origin adds no attack surface — while Firefox MV3, where
/// host permissions are not granted at install, needs the CORS path to work.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CorsMode {
    /// No CORS headers at all (flag absent, or `ANTD_CORS=false`).
    Disabled,
    /// Browser-extension origins only (bare `--cors` / `ANTD_CORS=true`).
    Extensions,
    /// Extension origins plus these exact web origins.
    AllowList(Vec<String>),
    /// Any origin (`--cors '*'`). Unsafe outside development.
    AllowAny,
}

impl Config {
    /// Parse `--cors` / `ANTD_CORS` into a [`CorsMode`].
    ///
    /// Accepts bool-style values (`true`/`false`, `1`/`0`, `on`/`off`,
    /// `yes`/`no`) for backward compatibility with the old boolean flag,
    /// `*`, or a comma-separated list of exact origins.
    pub fn cors_mode(&self) -> Result<CorsMode, String> {
        let Some(raw) = &self.cors else {
            return Ok(CorsMode::Disabled);
        };
        let entries: Vec<&str> = raw
            .split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .collect();
        if entries.is_empty() {
            return Ok(CorsMode::Disabled);
        }
        if entries.len() == 1 {
            match entries[0].to_ascii_lowercase().as_str() {
                "true" | "1" | "on" | "yes" => return Ok(CorsMode::Extensions),
                "false" | "0" | "off" | "no" => return Ok(CorsMode::Disabled),
                _ => {}
            }
        }
        if entries.contains(&"*") {
            if entries.len() > 1 {
                return Err("--cors: '*' cannot be combined with other origins".into());
            }
            return Ok(CorsMode::AllowAny);
        }
        let mut origins = Vec::with_capacity(entries.len());
        for entry in entries {
            let Some((scheme, rest)) = entry.split_once("://") else {
                return Err(format!(
                    "--cors: '{entry}' is not an origin — expected scheme://host[:port], \
                     e.g. http://127.0.0.1:8000 (or '*' to allow any origin)"
                ));
            };
            if scheme.is_empty() || rest.is_empty() || rest.contains('/') {
                return Err(format!(
                    "--cors: '{entry}' is not an origin — origins have no path or \
                     trailing slash, e.g. http://127.0.0.1:8000"
                ));
            }
            // Scheme and host are case-insensitive; browsers serialize the
            // Origin header lowercase, so normalize for the exact match.
            origins.push(entry.to_ascii_lowercase());
        }
        Ok(CorsMode::AllowList(origins))
    }

    /// Resolve the REST listen address, applying --rest-port override if set.
    pub fn resolved_rest_addr(&self) -> Result<std::net::SocketAddr, String> {
        let mut addr: std::net::SocketAddr = self
            .rest_addr
            .parse()
            .map_err(|e| format!("invalid REST address: {e}"))?;
        if let Some(port) = self.rest_port {
            addr.set_port(port);
        }
        Ok(addr)
    }

    /// Resolve the gRPC listen address, applying --grpc-port override if set.
    pub fn resolved_grpc_addr(&self) -> Result<std::net::SocketAddr, String> {
        let mut addr: std::net::SocketAddr = self
            .grpc_addr
            .parse()
            .map_err(|e| format!("invalid gRPC address: {e}"))?;
        if let Some(port) = self.grpc_port {
            addr.set_port(port);
        }
        Ok(addr)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mode(args: &[&str]) -> Result<CorsMode, String> {
        let argv: Vec<&str> = std::iter::once("antd")
            .chain(args.iter().copied())
            .collect();
        Config::parse_from(argv).cors_mode()
    }

    #[test]
    fn absent_flag_disables_cors() {
        assert_eq!(mode(&[]), Ok(CorsMode::Disabled));
    }

    #[test]
    fn bare_flag_allows_extensions_only() {
        assert_eq!(mode(&["--cors"]), Ok(CorsMode::Extensions));
    }

    #[test]
    fn bool_values_keep_old_env_contract() {
        assert_eq!(mode(&["--cors", "true"]), Ok(CorsMode::Extensions));
        assert_eq!(mode(&["--cors", "1"]), Ok(CorsMode::Extensions));
        assert_eq!(mode(&["--cors", "false"]), Ok(CorsMode::Disabled));
        assert_eq!(mode(&["--cors", "0"]), Ok(CorsMode::Disabled));
        assert_eq!(mode(&["--cors", ""]), Ok(CorsMode::Disabled));
    }

    #[test]
    fn star_allows_any_origin() {
        assert_eq!(mode(&["--cors", "*"]), Ok(CorsMode::AllowAny));
    }

    #[test]
    fn star_cannot_be_combined() {
        assert!(mode(&["--cors", "*,http://127.0.0.1:8000"]).is_err());
    }

    #[test]
    fn origin_list_is_parsed_and_lowercased() {
        assert_eq!(
            mode(&["--cors", "HTTP://Example.com, http://127.0.0.1:8000"]),
            Ok(CorsMode::AllowList(vec![
                "http://example.com".into(),
                "http://127.0.0.1:8000".into(),
            ]))
        );
    }

    #[test]
    fn origins_with_path_or_missing_scheme_are_rejected() {
        assert!(mode(&["--cors", "127.0.0.1:8000"]).is_err());
        assert!(mode(&["--cors", "http://127.0.0.1:8000/"]).is_err());
        assert!(mode(&["--cors", "http://127.0.0.1:8000/app"]).is_err());
    }
}
