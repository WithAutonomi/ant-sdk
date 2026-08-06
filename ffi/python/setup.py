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
"""

from setuptools import setup
from setuptools.dist import Distribution

try:  # setuptools >= 70.1 vendors bdist_wheel
    from setuptools.command.bdist_wheel import bdist_wheel
except ImportError:  # older: fall back to the wheel package
    from wheel.bdist_wheel import bdist_wheel


class BinaryDistribution(Distribution):
    # The wheel carries a native library (libant_ffi.{so,dylib,dll}). Declaring
    # ext modules routes the package into platlib (not purelib) and forces a
    # platform tag — required for the wheel to be platlib-compliant so that
    # `auditwheel repair` will accept and retag it on Linux.
    def has_ext_modules(self):
        return True


class PlatformWheel(bdist_wheel):
    def get_tag(self):
        # Valid for any Python 3 / any ABI (pure ctypes), pinned to this
        # platform. Platform component is whatever bdist_wheel resolved (or the
        # --plat-name override on the command line).
        _python, _abi, plat = super().get_tag()
        return "py3", "none", plat


setup(distclass=BinaryDistribution, cmdclass={"bdist_wheel": PlatformWheel})
