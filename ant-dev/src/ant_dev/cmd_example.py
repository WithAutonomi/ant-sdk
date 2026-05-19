"""``ant dev example <name>`` -- Run a named SDK example.

The dispatcher uses a per-language adapter table so adding a new SDK is
a single-entry change.  Each adapter declares:

  * ``examples`` -- mapping of short names (``data``, ``chunks`` ...) to
    whatever the language wants to identify the example (filename, gradle
    argument, cargo example name, ...).
  * ``cwd_subdir`` -- subdirectory of the SDK root where commands should
    run.  Most SDKs run from their own root (``antd-py``); a few (Go,
    Elixir) want the examples subdir.
  * ``prep`` -- optional list of build/install commands run once before
    ``run``.  Each entry is a callable taking the resolved cwd and
    returning ``list[str]``.
  * ``run`` -- callable returning the argv for a given example.

Adapters are intentionally small -- if a language needs anything fancier
than this, prefer a small helper script in the SDK directory rather than
extending the dispatcher.

Closes WithAutonomi/ant-sdk#65.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from .env import find_sdk_root


Argv = list[str]
RunFn = Callable[[Path, str], Argv]
PrepFn = Callable[[Path], Argv]


@dataclass
class Adapter:
    sdk_dir: str
    examples: dict[str, str]
    run: RunFn
    cwd_subdir: str = ""
    prep: list[PrepFn] = field(default_factory=list)
    skip_reason: str = ""


def _venv_python() -> str:
    return sys.executable


LANGUAGES: dict[str, Adapter] = {
    "python": Adapter(
        sdk_dir="antd-py",
        examples={
            "connect": "01_connect.py", "data": "02_data.py",
            "chunks": "03_chunks.py", "files": "04_files.py",
            "private": "06_private_data.py",
            "external_signer": "07_external_signer.py",
        },
        run=lambda cwd, f: [_venv_python(), f"examples/{f}"],
    ),
    "csharp": Adapter(
        sdk_dir="antd-csharp",
        cwd_subdir="Examples",
        examples={
            "connect": "1", "data": "2", "chunks": "3",
            "files": "4", "private": "6", "all": "all",
        },
        run=lambda cwd, n: ["dotnet", "run", "--", n],
    ),
    "go": Adapter(
        sdk_dir="antd-go",
        cwd_subdir="examples",
        examples={"connect": "01-connect", "data": "02-data", "files": "03-files"},
        run=lambda cwd, subdir: ["go", "run", f"./{subdir}"],
    ),
    "js": Adapter(
        sdk_dir="antd-js",
        examples={
            "connect": "01-connect.ts", "data": "02-data.ts",
            "chunks": "03-chunks.ts", "files": "04-files.ts",
            "private": "06-private-data.ts",
            "external_signer": "07-external-signer.ts",
        },
        prep=[lambda cwd: ["npm", "install", "--no-audit", "--no-fund"]],
        run=lambda cwd, f: ["npx", "--yes", "tsx", f"examples/{f}"],
    ),
    "ruby": Adapter(
        sdk_dir="antd-ruby",
        examples={
            "connect": "01_connect.rb", "data": "02_data.rb",
            "chunks": "03_chunks.rb", "files": "04_files.rb",
            "private": "06_private_data.rb",
        },
        prep=[lambda cwd: ["bundle", "install"]],
        run=lambda cwd, f: ["bundle", "exec", "ruby", f"examples/{f}"],
    ),
    "php": Adapter(
        sdk_dir="antd-php",
        examples={
            "connect": "01-connect.php", "data": "02-data.php",
            "chunks": "03-chunks.php", "files": "04-files.php",
            "private": "06-private-data.php",
        },
        prep=[lambda cwd: ["composer", "install", "--no-interaction", "--no-progress"]],
        run=lambda cwd, f: ["php", f"examples/{f}"],
    ),
    "elixir": Adapter(
        sdk_dir="antd-elixir",
        cwd_subdir="examples",
        examples={
            "connect": "01_connect.exs", "data": "02_data.exs",
            "chunks": "03_chunks.exs", "files": "04_files.exs",
            "private": "06_private_data.exs",
        },
        run=lambda cwd, f: ["elixir", f],
    ),
    "lua": Adapter(
        sdk_dir="antd-lua",
        examples={
            "connect": "01-connect.lua", "data": "02-data.lua",
            "chunks": "03-chunks.lua", "files": "04-files.lua",
            "private": "06-private-data.lua",
        },
        prep=[lambda cwd: ["luarocks", "--local", "--lua-version=5.4", "make"]],
        # `luarocks --local make` installs into ~/.luarocks, which lua5.4
        # doesn't pick up by default. Source `luarocks path` so LUA_PATH /
        # LUA_CPATH point at the freshly-installed rocks.
        run=lambda cwd, f: [
            "bash", "-c",
            'eval "$(luarocks --local --lua-version=5.4 path)" && exec lua5.4 "examples/$1"',
            "--", f,
        ],
    ),
    "cpp": Adapter(
        sdk_dir="antd-cpp",
        examples={
            "connect": "01-connect", "data": "02-data",
            "chunks": "03-chunks", "files": "04-files",
            "private": "06-private-data",
        },
        prep=[
            lambda cwd: ["cmake", "-S", ".", "-B", "build",
                         "-DCMAKE_BUILD_TYPE=Release"],
            lambda cwd: ["cmake", "--build", "build", "-j"],
        ],
        run=lambda cwd, target: [f"./build/{target}"],
    ),
    "java": Adapter(
        sdk_dir="antd-java",
        examples={
            "connect": "com.autonomi.examples.Example01Connect",
            "data": "com.autonomi.examples.Example02PublicData",
            "chunks": "com.autonomi.examples.Example03Chunks",
            "files": "com.autonomi.examples.Example03Files",
            "errors": "com.autonomi.examples.Example05ErrorHandling",
            "private": "com.autonomi.examples.Example06PrivateData",
        },
        prep=[lambda cwd: ["bash", "gradlew", ":examples:build", "--no-daemon", "-q"]],
        run=lambda cwd, cls: ["bash", "gradlew", ":examples:run",
                              f"-PmainClass={cls}", "--no-daemon", "-q"],
    ),
    "kotlin": Adapter(
        sdk_dir="antd-kotlin",
        examples={"connect": "1", "data": "2", "chunks": "3",
                  "files": "4", "private": "6", "all": "all"},
        prep=[lambda cwd: ["bash", "gradlew", ":examples:build", "--no-daemon", "-q"]],
        run=lambda cwd, n: ["bash", "gradlew", ":examples:run",
                            f"--args={n}", "--no-daemon", "-q"],
    ),
    "dart": Adapter(
        sdk_dir="antd-dart",
        examples={
            "connect": "01_connect.dart", "data": "02_data.dart",
            "chunks": "03_chunks.dart", "files": "04_files.dart",
            "private": "06_private_data.dart",
        },
        prep=[lambda cwd: ["dart", "pub", "get"]],
        run=lambda cwd, f: ["dart", "run", f"example/{f}"],
    ),
    "rust": Adapter(
        sdk_dir="antd-rust",
        examples={
            "connect": "01-connect", "data": "02-data",
            "chunks": "03-chunks", "files": "04-files",
            "private": "06-private-data",
            "external_signer": "07-external-signer",
        },
        run=lambda cwd, name: ["cargo", "run", "--release", "--quiet",
                               "--example", name],
    ),
    "zig": Adapter(
        sdk_dir="antd-zig",
        examples={
            "connect": "01-connect", "data": "02-data",
            "chunks": "03-chunks", "files": "04-files",
            "private": "06-private-data",
        },
        run=lambda cwd, name: ["zig", "build", f"run-{name}"],
    ),
    "swift": Adapter(
        sdk_dir="antd-swift",
        examples={
            "connect": "1", "data": "2", "chunks": "3",
            "files": "4", "private": "6", "all": "all",
        },
        prep=[lambda cwd: ["swift", "build"]],
        run=lambda cwd, n: ["swift", "run", "AntdExamples", n],
    ),
}


def _list_languages() -> str:
    return ", ".join(sorted(LANGUAGES.keys()))


def run(args) -> None:
    name = args.name.lower()
    lang = args.language
    sdk_root = find_sdk_root()

    adapter = LANGUAGES.get(lang)
    if adapter is None:
        print(f"Unknown language: {lang}")
        print(f"Available: {_list_languages()}")
        sys.exit(1)

    if adapter.skip_reason:
        print(f"Skipping {lang}: {adapter.skip_reason}")
        return

    cwd = sdk_root / adapter.sdk_dir
    if adapter.cwd_subdir:
        cwd = cwd / adapter.cwd_subdir
    if not cwd.exists():
        print(f"SDK directory not found: {cwd}")
        sys.exit(1)

    if name == "all":
        for short_name in adapter.examples:
            print(f"\n{'=' * 40}\n  Running {lang}/{short_name}\n{'=' * 40}\n")
            _run_one(adapter, cwd, short_name)
        return

    if name not in adapter.examples:
        print(f"Unknown example for {lang}: {name}")
        print(f"Available: {', '.join(adapter.examples)}, all")
        sys.exit(1)

    _run_one(adapter, cwd, name)


def _run_one(adapter: Adapter, cwd: Path, short_name: str) -> None:
    for prep in adapter.prep:
        cmd = prep(cwd) if callable(prep) else list(prep)
        if shutil.which(cmd[0]) is None:
            print(f"prep tool not on PATH: {cmd[0]}")
            sys.exit(1)
        r = subprocess.run(cmd, cwd=str(cwd))
        if r.returncode != 0:
            sys.exit(r.returncode)

    argv = adapter.run(cwd, adapter.examples[short_name])
    r = subprocess.run(argv, cwd=str(cwd))
    if r.returncode != 0:
        sys.exit(r.returncode)
