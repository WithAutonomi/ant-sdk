# Security Policy

Thanks for taking the time to help keep ant-sdk and its users safe.

This document covers what ant-sdk considers in-scope for security reports, how to report a vulnerability, and the response timeline you can expect.

## Threat model

ant-sdk consists of:

- **antd** — a local gateway daemon (Rust, REST + gRPC) that bridges applications to the Autonomi decentralized network and signs payment transactions when a wallet key is configured.
- **Language SDKs** — REST and gRPC clients across 15+ languages, plus an MCP server and developer CLI.

ant-sdk is designed around the following trust assumptions:

- **antd is a local daemon, not a network service.** It binds to `127.0.0.1` only by default on both REST and gRPC. Exposing it on a non-loopback address is an explicit, opt-in operator decision.
- **antd has no built-in authentication on REST or gRPC.** The security model assumes the host running antd is trusted and that network exposure is opt-in. If you bind antd to an externally reachable interface, you must firewall it; ant-sdk does not provide auth and does not aim to.
- **The wallet private key is read from the `AUTONOMI_WALLET_KEY` environment variable.** It is never logged, never persisted to disk by antd, and never returned over the REST or gRPC API. External-signer mode lets applications keep the key out of antd entirely; see the [external-signer flow](docs/external-signer-flow.md).
- **Upstream cryptography and consensus live in `ant-core`, `ant-protocol`, and `self_encryption`.** ant-sdk does not implement its own primitives; it consumes them.

Most defaults assume the operator runs antd alongside their application on a single trusted machine. Multi-tenant hosts, public LAN deployment, and container networking that exposes antd outside the pod are operator-responsibility scenarios.

## What's in scope

The following are within scope for security reports against ant-sdk:

- Remote code execution or privilege escalation in **antd** reachable via REST, gRPC, the external-signer flow, or the wallet routes.
- **Wallet-key leakage** through logs, error messages, daemon responses, process listings, the port file, crash dumps, or any other channel.
- **Authentication or authorization bypass** on any auth layer that ant-sdk introduces in the future. (At present antd has none — see the threat model.)
- **Cryptographic correctness flaws** in code paths owned by ant-sdk: the external-signer two-phase upload flow, payment-mode handling, the SDKs' wire-level handling of upload/download artifacts.
- **Supply-chain compromise** of ant-sdk build, release, or distribution pipelines — including malicious dependency updates, tampered release artifacts, or compromised CI workflows.
- **Sensitive-data exposure** in language-SDK code paths: SDK request/response shapes that inadvertently include secrets, telemetry that ships credentials, sample code that demonstrates insecure patterns by default.

## What's out of scope

We will redirect or close reports about the following:

- **Misconfiguration where the operator chose to bind antd to a non-loopback interface without a firewall.** antd is documented as loopback-by-default and unauthenticated; binding it externally without isolation is an operator decision and not a vulnerability in ant-sdk.
- **Issues in upstream `ant-core`, `ant-protocol`, `self_encryption`, or `evmlib`.** Please report these to their respective repositories; we will help redirect when needed.
- **Network-level attacks against the Autonomi P2P network itself** (e.g. Sybil, eclipse, routing manipulation). Out of scope for ant-sdk; in scope for `ant-node` / `ant-protocol`.
- **Issues in third-party EVM RPC endpoints, hosted wallets, or external signers** that an application chooses to use with ant-sdk.
- **Theoretical issues without a concrete impact** (e.g. "DH parameters could be longer"), best-practice deviations that don't enable an attack, or findings that require an attacker to already control the host.
- **Self-XSS, missing security headers on local-only endpoints, missing rate limits on documented-unauthenticated routes** — these are tracked separately as hardening work and are not handled through the disclosure process.

## How to report

**Preferred channel: GitHub Private Vulnerability Reporting.**

Open a private report at: <https://github.com/WithAutonomi/ant-sdk/security/advisories/new>

PVR keeps the report private until coordinated disclosure, gives us a structured place to track the fix, and avoids any email-routing ambiguity.

**Fallback channel: email.**

If you cannot use PVR (no GitHub account, organizational policy, etc.), email **<dev@maidsafe.net>** with the subject prefix `[ant-sdk security]`. Mark the message confidential. PGP not currently offered; we will move the conversation to PVR once you confirm an account.

**Please include**, where possible:

- ant-sdk version (commit SHA, release tag, or daemon `/health` response)
- Affected component (antd REST, antd gRPC, a specific SDK by name)
- A minimal reproduction (curl invocation, code snippet, or PoC binary)
- Your assessment of impact and any mitigating factors
- Whether you wish to be publicly credited in the eventual advisory

**What you can expect from us:**

- **Acknowledgement** within 3 business days.
- **Triage assessment** (in-scope / out-of-scope, severity, planned fix path) within 10 business days.
- **Default disclosure window: 90 days** from initial report. We may request an extension if the fix is complex or requires coordinated upstream releases; we'll discuss this with you transparently rather than going silent.
- **Coordinated disclosure**: once a fix ships, we publish a GitHub Security Advisory crediting the reporter (unless they opt out).

## Supported versions

| Version line | Status | Security fixes |
| --- | --- | --- |
| **v1.x** | Current stable | Yes |
| Pre-v1.0 (any) | Unsupported | No — please upgrade |

Until v1.0 ships, the current `main` branch is treated as the supported line. After v1.0, only the most recent v1.x minor receives security backports; we will reassess this policy when v2 work begins.

## Dependency hygiene

ant-sdk runs `cargo audit --locked` in CI against every push and pull request, gating merges on a clean advisory database. Post-v1.0 we plan to extend this with `cargo-deny` (for license and source policy in addition to advisories) and per-ecosystem scanning for the non-Rust SDKs (`npm audit`, `pip-audit`, `govulncheck`, etc.).

## Hardening recommendations for operators

For deployments that need network-reachable antd (CI runners, containerized services, shared developer environments):

1. **Keep the loopback default unless you have a specific reason not to.** The simplest secure deployment is `antd` on the same host as the consuming app.
2. **If you must bind externally**, restrict access at the network layer (firewall, security group, container network policy, mTLS proxy in front of antd) — antd itself will not.
3. **Use external-signer mode** in any environment where you would rather not hand antd the wallet key. See the [external-signer flow](docs/external-signer-flow.md).
4. **Set `ANTD_LOG_LEVEL=info`** (default) or stricter in production. Trace/debug levels can include request bodies; never run those in environments processing real funds.
5. **Verify release-artifact checksums** against `SHA256SUMS` for every download. GPG signatures are planned for a future release; until then, treat the SHA256 line as the primary integrity check.

## Acknowledgements

We are grateful for the time researchers spend looking at ant-sdk in good faith. Reporters who help us ship a fix will be credited in the published advisory by default.
