"""``ant dev init <language>`` — Scaffold a new project from templates."""

from __future__ import annotations

import sys
from pathlib import Path
from string import Template


TEMPLATE_DIR = Path(__file__).parent / "templates"


def run(args) -> None:
    lang = args.language
    name = args.name
    out_dir = Path(args.dir) if args.dir else Path.cwd() / name

    if out_dir.exists() and any(out_dir.iterdir()):
        print(f"Directory already exists and is not empty: {out_dir}")
        sys.exit(1)

    if lang == "python":
        _scaffold_python(name, out_dir)
    elif lang == "csharp":
        _scaffold_csharp(name, out_dir)

    print(f"Project scaffolded at: {out_dir}")
    print()
    if lang == "python":
        print("Next steps:")
        print(f"  cd {name}")
        print("  pip install -e .")
        print("  python main.py")
    else:
        print("Next steps:")
        print(f"  cd {name}")
        print("  dotnet run")


def _scaffold_python(name: str, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    # pyproject.toml
    tmpl = (TEMPLATE_DIR / "python" / "pyproject.toml.tmpl").read_text()
    content = Template(tmpl).safe_substitute(project_name=name)
    (out_dir / "pyproject.toml").write_text(content)

    # main.py
    tmpl = (TEMPLATE_DIR / "python" / "main.py.tmpl").read_text()
    content = Template(tmpl).safe_substitute(project_name=name)
    (out_dir / "main.py").write_text(content)


def _scaffold_csharp(name: str, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    # .csproj
    tmpl = (TEMPLATE_DIR / "csharp" / "Project.csproj.tmpl").read_text()
    content = Template(tmpl).safe_substitute(project_name=name)
    (out_dir / f"{name}.csproj").write_text(content)

    # Program.cs
    tmpl = (TEMPLATE_DIR / "csharp" / "Program.cs.tmpl").read_text()
    content = Template(tmpl).safe_substitute(project_name=name)
    (out_dir / "Program.cs").write_text(content)
