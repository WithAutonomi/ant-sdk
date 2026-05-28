fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_root = std::path::Path::new("../antd/proto");

    tonic_build::configure().build_server(true).compile_protos(
        &[
            "antd/v1/common.proto",
            "antd/v1/health.proto",
            "antd/v1/data.proto",
            "antd/v1/chunks.proto",
            "antd/v1/files.proto",
            "antd/v1/upload.proto",
            "antd/v1/events.proto",
            "antd/v1/wallet.proto",
        ],
        &[proto_root],
    )?;

    Ok(())
}
