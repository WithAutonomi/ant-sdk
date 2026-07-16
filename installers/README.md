# antd desktop installers

Signed, autostart-capable installers for the **antd daemon** that the Autonomi
browser extension downloads. One installer per desktop OS, published as GitHub
Release assets under fixed filenames.

| OS | Asset | Arch | Autostart mechanism |
|----|-------|------|---------------------|
| Windows | `antd-windows-x64-setup.msi` | x64 | HKLM `…\CurrentVersion\Run` value (hidden launcher) |
| macOS | `antd-macos.pkg` | arm64 | LaunchAgent `/Library/LaunchAgents/com.autonomi.antd.plist` |
| Linux | `antd-linux-x64.deb` (primary) | x64 | systemd `--user` unit `antd.service` |
| Linux | `antd-linux-x64.rpm` | x64 | systemd `--user` unit `antd.service` |
| Linux | `antd-linux-install.sh` | x64/arm64 | systemd `--user` unit `antd.service` |

Each installer: installs `antd` → registers **per-user login autostart** running
`antd --cors` → starts it once. Autostart is always **per-user / login-session**,
never root/boot — otherwise antd's `daemon.port`/config land in the wrong profile
and the extension can't find the daemon.

## Runtime contract (what the extension needs)

1. antd version ≥ 0.9.2.
2. Started with `--cors` (browser-origin REST is blocked without it).
3. Listening on `127.0.0.1:8082` (default).
4. Auto-started on login; survives reboot.
5. Runs in the user's session → per-user data dir:
   - Windows `%APPDATA%\ant\sdk\` · macOS `~/Library/Application Support/ant/sdk/`
     · Linux `~/.local/share/ant/sdk/`.

## Layout

```
installers/
├── common/metadata.env        # asset names, paths, com.autonomi.antd label
├── linux/
│   ├── nfpm.yaml              # one config → .deb + .rpm
│   ├── build-deb-rpm.sh       # renders config (envsubst) + runs nfpm
│   ├── systemd/antd.service   # per-user unit (ExecStart=/usr/bin/antd --cors)
│   ├── scripts/{postinstall,preremove,postremove}.sh
│   └── install.sh             # generic downloader (asset antd-linux-install.sh)
├── macos/
│   ├── com.autonomi.antd.plist
│   ├── scripts/postinstall    # launchctl bootstrap into the console user's GUI session
│   └── build-pkg.sh           # pkgbuild/productbuild + codesign/productsign/notarize/staple
└── windows/
    ├── antd.wxs               # WiX v5: install + Run-key autostart + launch-on-finish
    ├── antd-launch.vbs        # hidden launcher (no console window)
    └── build-msi.ps1          # sign antd.exe → wix build (x64) → sign .msi
```

## Building locally

**Linux** (needs Go for nfpm; produces both packages):
```sh
go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest
installers/linux/build-deb-rpm.sh --bin path/to/antd --version 0.10.0 --out dist
```

**macOS** (on macOS; signing/notarization skipped if the env vars below are unset):
```sh
installers/macos/build-pkg.sh --bin path/to/antd --version 0.10.0 --out dist
```

**Windows** (on Windows; .NET SDK; signing skipped if smctl/SM_KEYPAIR_ALIAS absent):
```powershell
installers\windows\build-msi.ps1 -BinDir path\to\dir-with-antd.exe -Version 0.10.0 -OutDir dist
```

The generic Linux script is self-contained — end users just run it:
```sh
./antd-linux-install.sh            # latest release for their arch
./antd-linux-install.sh --uninstall
```

## Release CI (`.github/workflows/release.yml`)

Triggered by pushing a `v*` tag. After the existing `build` matrix:

- **`package-linux`** builds `.deb` + `.rpm` (nfpm) and stages `install.sh`.
- **`package-macos`** codesigns the bare binary, builds + signs + notarizes the `.pkg`.
- **`package-windows`** signs `antd.exe`, builds + signs the `.msi`.
- **`release`** publishes the signed binaries + installers; **RC tags
  (`vX.Y.Z-rc.N`) publish as a GitHub pre-release** — the channel for testing the
  signing + installer pipeline before a stable release.

Signing steps are **gated on the relevant secrets being present**, so a run
without secrets still produces unsigned artifacts for pipeline testing.

### Required GitHub secrets (repo/org: `WithAutonomi/ant-sdk`)

The signing identities are reused from `maidsafe/autonomi`. Because that repo is
in a **different org**, these secrets must be **provisioned in this repo/org** by
an admin before signed releases work:

| Platform | Secrets |
|----------|---------|
| Windows (Authenticode via DigiCert SSM / Azure Trusted Signing) | `SM_HOST`, `SM_API_KEY`, `SM_CLIENT_CERT_B64`, `SM_CLIENT_CERT_PASSWORD`, `SM_KEYPAIR_ALIAS` |
| macOS (Developer ID Application + Installer, notarization) | `APPLE_APPLICATION_CERTIFICATE_P12_BASE64`, `APPLE_APPLICATION_CERTIFICATE_PASSWORD`, `APPLE_INSTALLER_CERTIFICATE_P12_BASE64`, `APPLE_INSTALLER_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_NOTARIZATION_PASSWORD`, `APPLE_TEAM_ID` |
| Linux (optional GPG of deb/rpm) | `GPG_PRIVATE_KEY`, `GPG_PASSPHRASE` |

## Architecture

The extension's `detectOs()` distinguishes only Windows / macOS / Linux — no
arch detection — so each OS maps to exactly one auto-selected asset. Current
matrix: macOS **arm64 only**, Windows + Linux **x64**. Intel-Mac / ARM-Linux
support needs both extra builds and an extension change to select per-arch.

## Coordination with the browser extension (separate repo)

The extension is in a different repository. Only the `.deb` is wired to its
download button today; the `.rpm` and `install.sh` are published and documented
but require a future extension change to be selected per distro. After cutting a
release, confirm/update the extension's `src/shared/constants.ts`:

- `ANTD_RELEASE_REPO` = `WithAutonomi/ant-sdk`
- `ANTD_RELEASE_TAG` → the published tag (repo is at 0.10.0; the spec's `v0.9.2`
  is stale — point it at the real release tag)
- `MIN_ANTD_VERSION` (≥ 0.9.2)
- `ANTD_INSTALLER_ASSETS` → the fixed filenames above
- `ANTD_RUN_GUIDE[].installPath` → `C:\Program Files\Autonomi\antd\antd.exe`,
  `/usr/local/bin/antd` (macOS), `/usr/bin/antd` (Linux)

## Acceptance criteria (per OS, clean machine)

1. Download via the extension → correct asset downloads.
2. Run installer with defaults.
3. Within seconds, no reboot, extension shows **Connected**.
4. antd listening on `127.0.0.1:8082`, answers `GET /health`.
5. Started with `--cors` (extension origin requests succeed).
6. `daemon.port`/config under the per-user data dir.
7. Reboot / re-login → antd running again automatically.
8. No lingering console window (Windows).
9. Uninstall removes the autostart entry and stops the daemon.
