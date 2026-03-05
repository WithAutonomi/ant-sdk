use autonomi::Client;
use ant_evm::EvmWallet;

#[derive(Clone)]
pub struct AppState {
    pub client: Client,
    pub wallet: EvmWallet,
    pub network: String,
}
