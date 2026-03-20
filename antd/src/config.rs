use clap::Parser;

#[derive(Parser, Debug, Clone)]
#[command(name = "antd", about = "REST + gRPC gateway for Saorsa network")]
pub struct Config {
    /// REST API listen address
    #[arg(long, default_value = "0.0.0.0:8082", env = "ANTD_REST_ADDR")]
    pub rest_addr: String,

    /// gRPC listen address
    #[arg(long, default_value = "0.0.0.0:50051", env = "ANTD_GRPC_ADDR")]
    pub grpc_addr: String,

    /// Network mode: default, local
    #[arg(long, default_value = "default", env = "ANTD_NETWORK")]
    pub network: String,

    /// Comma-separated bootstrap peer multiaddrs
    #[arg(long, env = "ANTD_PEERS", value_delimiter = ',')]
    pub peers: Option<Vec<String>>,

    /// Enable CORS headers
    #[arg(long, default_value_t = false, env = "ANTD_CORS")]
    pub cors: bool,
}
