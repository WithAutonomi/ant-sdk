//! EVM configuration defaults.
//!
//! Resolves `(rpc_url, payment_token_address, payment_vault_address)` from a
//! combination of the `--network` flag, `EVM_NETWORK` env override, and
//! individual `EVM_*` env vars. Individual env vars always win over presets.
//!
//! Presets:
//!   - `arbitrum-one`: Arbitrum One mainnet
//!   - `arbitrum-sepolia`: Arbitrum Sepolia testnet
//!   - `local`: localhost:8545 with empty addresses (devnet tooling supplies
//!     these via env)
//!
//! If `EVM_NETWORK` is unset, the preset defaults to `local` when
//! `--network local` is supplied and `arbitrum-one` otherwise — so mainnet is
//! the well-lit path and opt-out rather than opt-in.
//!
//! Preset values mirror the canonical constants in
//! `autonomi/evmlib/src/lib.rs` so antd reads/writes the same on-chain state
//! as every other Autonomi component pointed at the same network. They are
//! duplicated (rather than pulled from `evmlib` accessors) because the
//! published `evmlib` crate does not yet expose them as `pub const`.

/// Arbitrum One mainnet defaults — `ARBITRUM_ONE_*` in `evmlib::lib`.
const ARBITRUM_ONE_RPC_URL: &str = "https://arb1.arbitrum.io/rpc";
const ARBITRUM_ONE_TOKEN: &str = "0xa78d8321B20c4Ef90eCd72f2588AA985A4BDb684";
const ARBITRUM_ONE_VAULT: &str = "0xB1b5219f8Aaa18037A2506626Dd0406a46f70BcC";

/// Arbitrum Sepolia testnet defaults — `ARBITRUM_SEPOLIA_TEST_*` in `evmlib::lib`.
const ARBITRUM_SEPOLIA_RPC_URL: &str = "https://sepolia-rollup.arbitrum.io/rpc";
const ARBITRUM_SEPOLIA_TOKEN: &str = "0x4bc1aCE0E66170375462cB4E6Af42Ad4D5EC689C";
const ARBITRUM_SEPOLIA_VAULT: &str = "0x7f0842a78f7d4085d975ba91d630d680f91b1295";

/// Resolved EVM configuration values ready to be passed to
/// [`evmlib::Network::new_custom`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EvmConfig {
    pub rpc_url: String,
    pub token_addr: String,
    pub vault_addr: String,
    /// Preset name used to pick defaults, purely for logging.
    pub preset: String,
}

/// Resolve EVM defaults from the real process environment.
pub fn resolve(network_name: &str) -> EvmConfig {
    resolve_with(network_name, |k| std::env::var(k).ok())
}

/// Testable variant — caller supplies the env lookup.
pub fn resolve_with<F>(network_name: &str, getenv: F) -> EvmConfig
where
    F: Fn(&str) -> Option<String>,
{
    let preset = getenv("EVM_NETWORK").unwrap_or_else(|| match network_name {
        "local" => "local".to_string(),
        _ => "arbitrum-one".to_string(),
    });

    let (def_rpc, def_token, def_vault) = match preset.as_str() {
        "arbitrum-one" => (
            ARBITRUM_ONE_RPC_URL.to_string(),
            ARBITRUM_ONE_TOKEN.to_string(),
            ARBITRUM_ONE_VAULT.to_string(),
        ),
        "arbitrum-sepolia" | "arbitrum-sepolia-test" => (
            ARBITRUM_SEPOLIA_RPC_URL.to_string(),
            ARBITRUM_SEPOLIA_TOKEN.to_string(),
            ARBITRUM_SEPOLIA_VAULT.to_string(),
        ),
        _ => (
            "http://127.0.0.1:8545".to_string(),
            String::new(),
            String::new(),
        ),
    };

    let rpc_url = getenv("EVM_RPC_URL").unwrap_or(def_rpc);
    let token_addr = getenv("EVM_PAYMENT_TOKEN_ADDRESS").unwrap_or(def_token);
    let vault_addr = getenv("EVM_PAYMENT_VAULT_ADDRESS")
        .or_else(|| getenv("EVM_DATA_PAYMENTS_ADDRESS"))
        .unwrap_or(def_vault);

    EvmConfig {
        rpc_url,
        token_addr,
        vault_addr,
        preset,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn env(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let map: HashMap<String, String> = pairs
            .iter()
            .map(|(k, v)| ((*k).to_string(), (*v).to_string()))
            .collect();
        move |k| map.get(k).cloned()
    }

    #[test]
    fn default_network_picks_arbitrum_one() {
        let cfg = resolve_with("default", env(&[]));
        assert_eq!(cfg.preset, "arbitrum-one");
        assert_eq!(cfg.rpc_url, "https://arb1.arbitrum.io/rpc");
        assert!(
            cfg.token_addr
                .eq_ignore_ascii_case("0xa78d8321B20c4Ef90eCd72f2588AA985A4BDb684"),
            "unexpected token addr: {}",
            cfg.token_addr
        );
        assert!(
            cfg.vault_addr
                .eq_ignore_ascii_case("0xB1b5219f8Aaa18037A2506626Dd0406a46f70BcC"),
            "unexpected vault addr: {}",
            cfg.vault_addr
        );
    }

    #[test]
    fn local_network_keeps_localhost_default() {
        let cfg = resolve_with("local", env(&[]));
        assert_eq!(cfg.preset, "local");
        assert_eq!(cfg.rpc_url, "http://127.0.0.1:8545");
        assert_eq!(cfg.token_addr, "");
        assert_eq!(cfg.vault_addr, "");
    }

    #[test]
    fn evm_network_sepolia_picks_sepolia_addresses() {
        let cfg = resolve_with("default", env(&[("EVM_NETWORK", "arbitrum-sepolia")]));
        assert_eq!(cfg.preset, "arbitrum-sepolia");
        assert_eq!(cfg.rpc_url, "https://sepolia-rollup.arbitrum.io/rpc");
        assert!(
            cfg.token_addr
                .eq_ignore_ascii_case("0x4bc1aCE0E66170375462cB4E6Af42Ad4D5EC689C"),
            "unexpected token addr: {}",
            cfg.token_addr
        );
    }

    #[test]
    fn evm_network_local_even_when_network_is_default() {
        let cfg = resolve_with("default", env(&[("EVM_NETWORK", "local")]));
        assert_eq!(cfg.preset, "local");
        assert_eq!(cfg.rpc_url, "http://127.0.0.1:8545");
    }

    #[test]
    fn individual_env_vars_override_preset() {
        let cfg = resolve_with(
            "default",
            env(&[
                ("EVM_RPC_URL", "https://custom.rpc.example/"),
                ("EVM_PAYMENT_TOKEN_ADDRESS", "0xdead"),
                ("EVM_PAYMENT_VAULT_ADDRESS", "0xbeef"),
            ]),
        );
        assert_eq!(cfg.rpc_url, "https://custom.rpc.example/");
        assert_eq!(cfg.token_addr, "0xdead");
        assert_eq!(cfg.vault_addr, "0xbeef");
        // Preset still reflects arbitrum-one because we didn't override EVM_NETWORK.
        assert_eq!(cfg.preset, "arbitrum-one");
    }

    #[test]
    fn vault_address_legacy_var_is_honoured() {
        let cfg = resolve_with("local", env(&[("EVM_DATA_PAYMENTS_ADDRESS", "0xfeedface")]));
        assert_eq!(cfg.vault_addr, "0xfeedface");
    }

    #[test]
    fn vault_address_new_var_beats_legacy_var() {
        let cfg = resolve_with(
            "local",
            env(&[
                ("EVM_PAYMENT_VAULT_ADDRESS", "0xaaaa"),
                ("EVM_DATA_PAYMENTS_ADDRESS", "0xbbbb"),
            ]),
        );
        assert_eq!(cfg.vault_addr, "0xaaaa");
    }

    #[test]
    fn arbitrary_network_name_defaults_to_arbitrum_one() {
        // If --network ever grows new names, they inherit the mainnet default
        // until EVM_NETWORK or individual overrides say otherwise.
        let cfg = resolve_with("some-future-network", env(&[]));
        assert_eq!(cfg.preset, "arbitrum-one");
    }
}
