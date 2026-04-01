use clap::Parser;

#[derive(Parser, Debug, Clone)]
#[command(name = "antd", about = "REST + gRPC gateway for Autonomi network")]
pub struct Config {
    /// REST API listen address
    #[arg(long, default_value = "0.0.0.0:8082", env = "ANTD_REST_ADDR")]
    pub rest_addr: String,

    /// gRPC listen address
    #[arg(long, default_value = "0.0.0.0:50051", env = "ANTD_GRPC_ADDR")]
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

    /// Enable CORS headers
    #[arg(long, default_value_t = false, env = "ANTD_CORS")]
    pub cors: bool,

    /// Log level: trace, debug, info, warn, error
    #[arg(long, default_value = "info", env = "ANTD_LOG_LEVEL")]
    pub log_level: String,
}

impl Config {
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
