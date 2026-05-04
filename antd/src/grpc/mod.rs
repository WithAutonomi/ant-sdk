use std::sync::Arc;

use tokio::net::TcpListener;
use tokio_stream::wrappers::TcpListenerStream;
use tonic::transport::Server;

use crate::state::AppState;

pub mod service;

use service::pb::{
    chunk_service_server::ChunkServiceServer, data_service_server::DataServiceServer,
    event_service_server::EventServiceServer, file_service_server::FileServiceServer,
    health_service_server::HealthServiceServer,
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
    let event_svc = EventServiceServer::new(service::EventServiceImpl {
        state: state.clone(),
    });
    let health_svc = HealthServiceServer::new(service::HealthServiceImpl {
        state: state.clone(),
    });

    let addr = listener.local_addr()?;
    tracing::info!("gRPC server listening on {addr}");

    Server::builder()
        .add_service(health_svc)
        .add_service(data_svc)
        .add_service(chunk_svc)
        .add_service(file_svc)
        .add_service(event_svc)
        .serve_with_incoming(TcpListenerStream::new(listener))
        .await?;

    Ok(())
}
