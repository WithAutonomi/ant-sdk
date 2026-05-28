use std::process::Command;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Capture short git SHA for /health diagnostics. Falls back to "" when
    // built outside a git checkout (e.g. crates.io source distribution) — the
    // /health endpoint reports the empty string in that case.
    let commit = Command::new("git")
        .args(["rev-parse", "--short=12", "HEAD"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default();
    println!("cargo:rustc-env=ANTD_BUILD_COMMIT={commit}");
    println!("cargo:rerun-if-changed=.git/HEAD");
    println!("cargo:rerun-if-changed=.git/refs/heads");

    tonic_build::configure()
        .build_client(false)
        .build_server(true)
        .compile_protos(
            &[
                "proto/antd/v1/health.proto",
                "proto/antd/v1/data.proto",
                "proto/antd/v1/chunks.proto",
                "proto/antd/v1/files.proto",
                "proto/antd/v1/events.proto",
                "proto/antd/v1/wallet.proto",
            ],
            &["proto"],
        )?;
    Ok(())
}
