use std::sync::Arc;

use tonic::transport::Server;

use crate::state::AppState;

pub mod service;

use service::pb::{
    chunk_service_server::ChunkServiceServer,
    data_service_server::DataServiceServer,
    event_service_server::EventServiceServer,
    file_service_server::FileServiceServer,
    graph_service_server::GraphServiceServer,
    health_service_server::HealthServiceServer,
    pointer_service_server::PointerServiceServer,
    register_service_server::RegisterServiceServer,
    scratchpad_service_server::ScratchpadServiceServer,
    vault_service_server::VaultServiceServer,
};

pub async fn serve(addr: std::net::SocketAddr, state: Arc<AppState>) -> Result<(), Box<dyn std::error::Error>> {
    let data_svc = DataServiceServer::new(service::DataServiceImpl { state: state.clone() });
    let chunk_svc = ChunkServiceServer::new(service::ChunkServiceImpl { state: state.clone() });
    let pointer_svc = PointerServiceServer::new(service::PointerServiceImpl { state: state.clone() });
    let scratchpad_svc = ScratchpadServiceServer::new(service::ScratchpadServiceImpl { state: state.clone() });
    let graph_svc = GraphServiceServer::new(service::GraphServiceImpl { state: state.clone() });
    let register_svc = RegisterServiceServer::new(service::RegisterServiceImpl { state: state.clone() });
    let vault_svc = VaultServiceServer::new(service::VaultServiceImpl { state: state.clone() });
    let file_svc = FileServiceServer::new(service::FileServiceImpl { state: state.clone() });
    let event_svc = EventServiceServer::new(service::EventServiceImpl { state: state.clone() });
    let health_svc = HealthServiceServer::new(service::HealthServiceImpl { network: state.network.clone() });

    tracing::info!("gRPC server listening on {addr}");

    Server::builder()
        .add_service(health_svc)
        .add_service(data_svc)
        .add_service(chunk_svc)
        .add_service(pointer_svc)
        .add_service(scratchpad_svc)
        .add_service(graph_svc)
        .add_service(register_svc)
        .add_service(vault_svc)
        .add_service(file_svc)
        .add_service(event_svc)
        .serve(addr)
        .await?;

    Ok(())
}
