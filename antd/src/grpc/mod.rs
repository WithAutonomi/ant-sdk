use std::sync::Arc;

use tokio::net::TcpListener;
use tokio_stream::wrappers::TcpListenerStream;
use tonic::transport::Server;

use crate::state::AppState;

pub mod service;

/// Largest ManifestService request accepted: the REST body limit.
const MAX_MANIFEST_GRPC_MESSAGE_BYTES: usize = 100 * 1024 * 1024;

use service::pb::{
    chunk_service_server::ChunkServiceServer, data_service_server::DataServiceServer,
    event_service_server::EventServiceServer, file_service_server::FileServiceServer,
    health_service_server::HealthServiceServer, manifest_service_server::ManifestServiceServer,
    upload_service_server::UploadServiceServer, verify_service_server::VerifyServiceServer,
    wallet_service_server::WalletServiceServer,
};

pub async fn serve(
    listener: TcpListener,
    state: Arc<AppState>,
) -> Result<(), Box<dyn std::error::Error>> {
    let data_svc = DataServiceServer::new(service::DataServiceImpl {
        state: state.clone(),
    });
    let chunk_svc = ChunkServiceServer::new(service::ChunkServiceImpl {
        state: state.clone(),
    });
    let file_svc = FileServiceServer::new(service::FileServiceImpl {
        state: state.clone(),
    });
    let upload_svc = UploadServiceServer::new(service::UploadServiceImpl {
        state: state.clone(),
    });
    let event_svc = EventServiceServer::new(service::EventServiceImpl {
        state: state.clone(),
    });
    let wallet_svc = WalletServiceServer::new(service::WalletServiceImpl {
        state: state.clone(),
    });
    let health_svc = HealthServiceServer::new(service::HealthServiceImpl {
        state: state.clone(),
    });
    // Entries carry raw quote/sidecar bytes; tonic's 4 MiB default would cap
    // a batch at ~600 entries where REST accepts MAX_VERIFY_ENTRIES.
    let verify_svc = VerifyServiceServer::new(service::VerifyServiceImpl)
        .max_decoding_message_size(crate::signed_quotes::MAX_VERIFY_GRPC_MESSAGE_BYTES);

    // A manifest is one document of up to 64 MiB, built or parsed whole;
    // accept requests up to the REST body limit rather than tonic's 4 MiB.
    let manifest_svc = ManifestServiceServer::new(service::ManifestServiceImpl {
        state: state.clone(),
    })
    .max_decoding_message_size(MAX_MANIFEST_GRPC_MESSAGE_BYTES);

    let addr = listener.local_addr()?;
    tracing::info!("gRPC server listening on {addr}");

    Server::builder()
        .add_service(health_svc)
        .add_service(data_svc)
        .add_service(chunk_svc)
        .add_service(file_svc)
        .add_service(upload_svc)
        .add_service(event_svc)
        .add_service(wallet_svc)
        .add_service(verify_svc)
        .add_service(manifest_svc)
        .serve_with_incoming(TcpListenerStream::new(listener))
        .await?;

    Ok(())
}
