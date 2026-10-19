#!/usr/bin/env python
"""Generate Python protobuf stubs from antd proto definitions.

Reads the .proto files this SDK ships from ../antd/proto/ and generates
Python stubs into src/antd/_proto/.

grpcio-tools bundles its own protoc and stamps both versions into the
generated files (GRPC_GENERATED_VERSION, "Protobuf Python Version"), so it
is pinned:

    pip install grpcio-tools==1.80.0

CI (.github/workflows/proto-drift.yml) runs this script and fails when the
committed stubs differ from its output, so commit whatever it changes.
"""

import re
import sys
from importlib import metadata
from pathlib import Path

GRPCIO_TOOLS_VERSION = "1.80.0"

# The antd/proto/antd/v1 files this SDK ships stubs for.
PROTOS = ["chunks", "common", "data", "events", "files", "health", "pointers", "upload", "wallet"]

# Resolve paths relative to this script
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
PROTO_SRC = PROJECT_DIR.parent / "antd" / "proto"
PROTO_OUT = PROJECT_DIR / "src" / "antd" / "_proto"


def main():
    if not PROTO_SRC.exists():
        print(f"ERROR: Proto source directory not found: {PROTO_SRC}")
        sys.exit(1)

    proto_files = [PROTO_SRC / "antd" / "v1" / f"{name}.proto" for name in PROTOS]
    missing = [str(f) for f in proto_files if not f.exists()]
    if missing:
        print(f"ERROR: proto files not found: {', '.join(missing)}")
        sys.exit(1)

    try:
        found = metadata.version("grpcio-tools")
    except metadata.PackageNotFoundError:
        found = None
    if found != GRPCIO_TOOLS_VERSION:
        print(
            f"ERROR: grpcio-tools {GRPCIO_TOOLS_VERSION} is required (found: {found or 'none'}). "
            f"Run: pip install grpcio-tools=={GRPCIO_TOOLS_VERSION}"
        )
        sys.exit(1)
    from grpc_tools import protoc

    print(f"Generating stubs for {len(proto_files)} proto files from {PROTO_SRC}")

    # Start from an empty package (keeping the __init__.py files), so a proto
    # dropped from PROTOS shows up as deleted stubs instead of lingering.
    stub_dir = PROTO_OUT / "antd" / "v1"
    stub_dir.mkdir(parents=True, exist_ok=True)
    for stale in stub_dir.glob("*_pb2*.py*"):
        stale.unlink()

    # Build protoc arguments
    args = [
        "grpc_tools.protoc",
        f"--proto_path={PROTO_SRC}",
        f"--python_out={PROTO_OUT}",
        f"--pyi_out={PROTO_OUT}",
        f"--grpc_python_out={PROTO_OUT}",
    ] + [str(f) for f in proto_files]

    print(f"Running protoc with {len(proto_files)} files...")
    result = protoc.main(args)

    if result != 0:
        print(f"ERROR: protoc failed with exit code {result}")
        sys.exit(result)

    # Fix relative imports in generated files (known grpc-tools issue)
    # Generated files use `import antd.v1.xxx_pb2` but we need
    # `from antd._proto.antd.v1 import xxx_pb2` for our package structure.
    fix_imports(PROTO_OUT)

    # Ensure __init__.py files exist
    for init_dir in [PROTO_OUT, PROTO_OUT / "antd", PROTO_OUT / "antd" / "v1"]:
        init_file = init_dir / "__init__.py"
        if not init_file.exists():
            init_file.touch()

    print("Proto stubs generated successfully!")


def fix_imports(output_dir: Path):
    """Fix import paths in generated protobuf files.

    grpc-tools generates imports like:
        from antd.v1 import common_pb2

    We need them to be:
        from antd._proto.antd.v1 import common_pb2
    """
    count = 0
    for py_file in output_dir.rglob("*.py"):
        content = py_file.read_text(encoding="utf-8")
        original = content

        # Fix "from antd.v1 import" -> "from antd._proto.antd.v1 import"
        content = re.sub(
            r"from antd\.v1 import",
            "from antd._proto.antd.v1 import",
            content,
        )

        # Fix "import antd.v1." -> "import antd._proto.antd.v1."
        content = re.sub(
            r"import antd\.v1\.",
            "import antd._proto.antd.v1.",
            content,
        )

        # Fix DESCRIPTOR references like antd.v1.xxx -> antd._proto.antd.v1.xxx
        # in _sym_db.RegisterFileDescriptor and similar calls
        content = re.sub(
            r"antd\.v1\.(\w+_pb2)",
            r"antd._proto.antd.v1.\1",
            content,
        )

        if content != original:
            py_file.write_text(content, encoding="utf-8", newline="\n")
            count += 1

    # Also fix .pyi files
    for pyi_file in output_dir.rglob("*.pyi"):
        content = pyi_file.read_text(encoding="utf-8")
        original = content

        content = re.sub(
            r"from antd\.v1 import",
            "from antd._proto.antd.v1 import",
            content,
        )

        content = re.sub(
            r"antd\.v1\.(\w+_pb2)",
            r"antd._proto.antd.v1.\1",
            content,
        )

        if content != original:
            pyi_file.write_text(content, encoding="utf-8", newline="\n")
            count += 1

    print(f"Fixed imports in {count} files")


if __name__ == "__main__":
    main()
