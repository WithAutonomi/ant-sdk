"""``ant dev example <name>`` — Run a named SDK example."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from .env import find_sdk_root


# Maps short names to example files
PYTHON_EXAMPLES = {
    "connect":     "01_connect.py",
    "data":        "02_data.py",
    "chunks":      "03_chunks.py",
    "files":       "04_files.py",
    "pointers":    "05_pointers.py",
    "scratchpads": "06_scratchpads.py",
    "graph":       "07_graph.py",
    "registers":   "08_registers.py",
    "vaults":      "09_vaults.py",
    "private":     "10_private_data.py",
}

CSHARP_EXAMPLES = {
    "connect": "1",
    "data": "2",
    "chunks": "3",
    "files": "4",
    "pointers": "5",
    "scratchpads": "6",
    "graph": "7",
    "registers": "8",
    "vaults": "9",
    "private": "10",
    "all": "all",
}


def run(args) -> None:
    name = args.name.lower()
    lang = args.language
    sdk_root = find_sdk_root()

    if lang == "python":
        _run_python(sdk_root, name)
    else:
        _run_csharp(sdk_root, name)


def _run_python(sdk_root: Path, name: str) -> None:
    examples_dir = sdk_root / "antd-py" / "examples"

    if name == "all":
        for short_name, filename in PYTHON_EXAMPLES.items():
            print(f"\n{'=' * 40}")
            print(f"  Running: {short_name}")
            print(f"{'=' * 40}\n")
            _run_one_python(examples_dir / filename)
        return

    filename = PYTHON_EXAMPLES.get(name)
    if not filename:
        print(f"Unknown example: {name}")
        print(f"Available: {', '.join(PYTHON_EXAMPLES.keys())}, all")
        sys.exit(1)

    _run_one_python(examples_dir / filename)


def _run_one_python(script: Path) -> None:
    if not script.exists():
        print(f"Example file not found: {script}")
        sys.exit(1)

    # Use 'python' on Windows, 'python3' on Unix
    python = "python" if sys.platform == "win32" else "python3"
    result = subprocess.run([python, str(script)])
    if result.returncode != 0:
        sys.exit(result.returncode)


def _run_csharp(sdk_root: Path, name: str) -> None:
    examples_dir = sdk_root / "antd-csharp" / "Examples"

    arg = CSHARP_EXAMPLES.get(name)
    if not arg:
        print(f"Unknown example: {name}")
        print(f"Available: {', '.join(CSHARP_EXAMPLES.keys())}")
        sys.exit(1)

    result = subprocess.run(
        ["dotnet", "run", "--", arg],
        cwd=str(examples_dir),
    )
    if result.returncode != 0:
        sys.exit(result.returncode)
