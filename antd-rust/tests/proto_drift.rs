//! Guards the committed gRPC code in `src/generated/antd.v1.rs`.
//!
//! The crate ships pre-generated prost/tonic code so that `cargo add antd-client`
//! works without protoc or the daemon's proto files. This test regenerates the
//! code from `../antd/proto` (the daemon's protos in the monorepo) and fails if
//! the committed file has drifted. To update after a proto change:
//!
//! ```text
//! ANTD_REGEN_PROTO=1 cargo test --test proto_drift
//! ```
//!
//! Outside the monorepo (e.g. the published crate) the protos are absent and
//! the test is a no-op.

use std::{env, fs, path::PathBuf};

const PROTOS: &[&str] = &[
    "antd/v1/common.proto",
    "antd/v1/health.proto",
    "antd/v1/data.proto",
    "antd/v1/chunks.proto",
    "antd/v1/files.proto",
    "antd/v1/upload.proto",
    "antd/v1/events.proto",
    "antd/v1/wallet.proto",
    "antd/v1/verify.proto",
];

fn normalize(s: &str) -> String {
    s.replace("\r\n", "\n")
}

#[test]
fn generated_grpc_code_matches_daemon_protos() {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let proto_root = manifest.join("..").join("antd").join("proto");
    if !proto_root.is_dir() {
        eprintln!(
            "proto_drift: {} not present (published crate?), skipping",
            proto_root.display()
        );
        return;
    }

    let out = env::temp_dir().join(format!("antd-client-protogen-{}", std::process::id()));
    fs::create_dir_all(&out).expect("create temp out dir");
    tonic_build::configure()
        .build_server(true)
        .out_dir(&out)
        .compile_protos(PROTOS, &[&proto_root])
        .expect("tonic-build failed — is `protoc` installed and on PATH?");
    let fresh = normalize(&fs::read_to_string(out.join("antd.v1.rs")).expect("read generated"));
    let _ = fs::remove_dir_all(&out);

    let committed_path = manifest.join("src").join("generated").join("antd.v1.rs");
    if env::var_os("ANTD_REGEN_PROTO").is_some() {
        fs::write(&committed_path, &fresh).expect("write regenerated code");
        eprintln!("proto_drift: rewrote {}", committed_path.display());
        return;
    }

    let committed = normalize(&fs::read_to_string(&committed_path).unwrap_or_default());
    assert!(
        fresh == committed,
        "src/generated/antd.v1.rs is stale relative to ../antd/proto.\n\
         Run `ANTD_REGEN_PROTO=1 cargo test --test proto_drift` and commit the result."
    );
}
