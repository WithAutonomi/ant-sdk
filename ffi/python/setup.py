"""Platform-tagged wheel build for the UniFFI Python bindings.

The generated bindings are pure-Python ctypes over a bundled native library
(libant_ffi.{so,dylib,dll}). That combination confuses the default wheel
machinery: setuptools sees no C extension and would tag the wheel
`py3-none-any` (a lie — the wheel carries a platform-specific binary), while a
`cpXY` ABI tag would be equally wrong (the ctypes module is ABI-independent and
works on any CPython/PyPy).

The correct tag is `py3-none-<platform>`: one wheel per OS/arch, valid for every
Python 3. This overrides bdist_wheel to force exactly that:
  * root_is_pure = False  -> emit a platform tag instead of `any`
  * get_tag() -> ("py3", "none", <platform>) -> Python- and ABI-agnostic

On Linux the resulting `linux_x86_64` tag is then handed to `auditwheel repair`,
which verifies the glibc floor, bundles any external libs, and retags to the
correct `manylinux_*` — auditwheel is the authority on portability, not us.

Two guardrails against publishable-looking but broken artifacts:
  * The generated module (ant_ffi/ant_ffi.py) and the native library are
    gitignored build outputs. Without them a wheel build would still "succeed",
    and the result installs cleanly then fails on `import ant_ffi` — so
    bdist_wheel refuses to run unless both are staged.
  * sdist is blocked outright: a source tarball would embed whichever native
    library this host built under a platform-neutral filename. This package
    ships as platform wheels only (`python -m build --wheel`).
"""

import sys
from pathlib import Path

from setuptools import setup
from setuptools.command.sdist import sdist
from setuptools.dist import Distribution

try:  # setuptools >= 70.1 vendors bdist_wheel
    from setuptools.command.bdist_wheel import bdist_wheel
except ImportError:  # older: fall back to the wheel package
    from wheel.bdist_wheel import bdist_wheel

_PKG_DIR = Path(__file__).resolve().parent / "ant_ffi"

# One native library per build host; the wheel scripts always build natively
# (the manylinux container, the macOS lipo fuse, the Windows MSVC build), so
# checking for the host platform's library name is exact, not a heuristic.
_NATIVE_LIB = {"win32": "ant_ffi.dll", "darwin": "libant_ffi.dylib"}.get(
    sys.platform, "libant_ffi.so"
)


def _require_generated_files():
    missing = [
        name for name in ("ant_ffi.py", _NATIVE_LIB) if not (_PKG_DIR / name).is_file()
    ]
    if missing:
        raise SystemExit(
            "error: generated build output(s) missing: "
            + ", ".join(f"ant_ffi/{m}" for m in missing)
            + ". A wheel built now would install but fail on `import ant_ffi`. "
            "Run ffi/scripts/build.sh (or a ffi/scripts/build-wheel-* script) to "
            "generate the bindings and native library first."
        )


class BinaryDistribution(Distribution):
    # The wheel carries a native library (libant_ffi.{so,dylib,dll}). Declaring
    # ext modules routes the package into platlib (not purelib) and forces a
    # platform tag — required for the wheel to be platlib-compliant so that
    # `auditwheel repair` will accept and retag it on Linux.
    def has_ext_modules(self):
        return True


class WheelOnlySdist(sdist):
    def run(self):
        raise SystemExit(
            "error: ant-sdk ships as platform wheels only — an sdist would embed "
            "this host's native library under a platform-neutral name. Use "
            "`python -m build --wheel`; sources live in the ant-sdk repository."
        )


class PlatformWheel(bdist_wheel):
    def run(self):
        _require_generated_files()
        super().run()

    def get_tag(self):
        # Valid for any Python 3 / any ABI (pure ctypes), pinned to this
        # platform. Platform component is whatever bdist_wheel resolved (or the
        # --plat-name override on the command line).
        _python, _abi, plat = super().get_tag()
        return "py3", "none", plat


setup(
    distclass=BinaryDistribution,
    cmdclass={"bdist_wheel": PlatformWheel, "sdist": WheelOnlySdist},
)
