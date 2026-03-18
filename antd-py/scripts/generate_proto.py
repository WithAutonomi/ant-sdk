#!/usr/bin/env python
"""Generate Python protobuf stubs from antd proto definitions.

Reads .proto files from ../antd/proto/ and generates Python stubs
into src/antd/_proto/.

Requires: pip install grpcio-tools
"""

import re
import sys
from pathlib import Path

# Resolve paths relative to this script
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
PROTO_SRC = PROJECT_DIR.parent / "antd" / "proto"
PROTO_OUT = PROJECT_DIR / "src" / "antd" / "_proto"


def main():
    if not PROTO_SRC.exists():
        print(f"ERROR: Proto source directory not found: {PROTO_SRC}")
        sys.exit(1)

    # Collect .proto files, excluding removed mutable data types
    EXCLUDED_PROTOS = {"pointers.proto", "scratchpads.proto", "registers.proto", "vaults.proto"}
    proto_files = sorted(
        f for f in PROTO_SRC.rglob("*.proto") if f.name not in EXCLUDED_PROTOS
    )
    if not proto_files:
        print(f"ERROR: No .proto files found in {PROTO_SRC}")
        sys.exit(1)

    print(f"Found {len(proto_files)} proto files in {PROTO_SRC}")

    # Ensure output directory exists
    PROTO_OUT.mkdir(parents=True, exist_ok=True)

    try:
        from grpc_tools import protoc
    except ImportError:
        print("ERROR: grpcio-tools not installed. Run: pip install grpcio-tools")
        sys.exit(1)

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
            py_file.write_text(content, encoding="utf-8")
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
            pyi_file.write_text(content, encoding="utf-8")
            count += 1

    print(f"Fixed imports in {count} files")


if __name__ == "__main__":
    main()
