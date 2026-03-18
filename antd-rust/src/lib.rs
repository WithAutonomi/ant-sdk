//! Rust REST client SDK for the antd daemon — the gateway to the Autonomi decentralized network.
//!
//! # Quick Start
//!
//! ```rust,no_run
//! use antd_client::{Client, DEFAULT_BASE_URL};
//!
//! #[tokio::main]
//! async fn main() -> Result<(), Box<dyn std::error::Error>> {
//!     let client = Client::new(DEFAULT_BASE_URL);
//!
//!     let health = client.health().await?;
//!     println!("OK: {}, Network: {}", health.ok, health.network);
//!
//!     let result = client.data_put_public(b"Hello, Autonomi!").await?;
//!     println!("Stored at {} (cost: {} atto)", result.address, result.cost);
//!
//!     let data = client.data_get_public(&result.address).await?;
//!     println!("Retrieved: {}", String::from_utf8_lossy(&data));
//!     Ok(())
//! }
//! ```

pub mod client;
pub mod errors;
pub mod grpc_client;
pub mod models;

#[cfg(test)]
mod tests;

#[cfg(test)]
mod grpc_tests;

pub use client::{Client, DEFAULT_BASE_URL, DEFAULT_TIMEOUT};
pub use errors::AntdError;
pub use grpc_client::{GrpcClient, DEFAULT_GRPC_ENDPOINT};
pub use models::*;
