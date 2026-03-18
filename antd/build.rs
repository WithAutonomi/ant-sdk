fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::configure()
        .build_client(false)
        .build_server(true)
        .compile_protos(
            &[
                "proto/antd/v1/health.proto",
                "proto/antd/v1/data.proto",
                "proto/antd/v1/chunks.proto",
                "proto/antd/v1/graph.proto",
                "proto/antd/v1/files.proto",
                "proto/antd/v1/events.proto",
            ],
            &["proto"],
        )?;
    Ok(())
}
