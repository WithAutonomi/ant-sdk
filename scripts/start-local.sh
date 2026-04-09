#!/usr/bin/env bash
set -euo pipefail

## Start a local ant devnet + antd gateway for testing.
##
## Prerequisites:
##   - Rust toolchain (cargo)
##   - ant-node repo cloned as sibling: ../ant-node
##     (or set ANT_NODE_DIR)
##   - python (for manifest parsing)
##
## Usage:
##   ./scripts/start-local.sh
##
## Tear down:
##   ./scripts/kill-local.sh

# ── Configuration ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANTD_DIR="$SDK_ROOT/antd"
MANIFEST_FILE="${TMPDIR:-/tmp}/devnet-manifest.json"

# Resolve ant-node directory
if [[ -n "${ANT_NODE_DIR:-}" ]]; then
    true  # already set
elif [[ -f "$SDK_ROOT/../ant-node/Cargo.toml" ]]; then
    ANT_NODE_DIR="$(cd "$SDK_ROOT/../ant-node" && pwd)"
else
    echo "ERROR: Cannot find ant-node repo."
    echo ""
    echo "Clone it as a sibling to ant-sdk:"
    echo "  cd $(dirname "$SDK_ROOT")"
    echo "  git clone https://github.com/WithAutonomi/ant-node.git"
    echo ""
    echo "Or set ANT_NODE_DIR to its location."
    exit 1
fi

# ── Colors ──
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;90m'
WHITE='\033[1;37m'
NC='\033[0m'

# Clean up old manifest
rm -f "$MANIFEST_FILE"

echo ""
echo -e "${CYAN}=== antd Local Test Environment ===${NC}"
echo ""
echo -e "${GRAY}  SDK:     $SDK_ROOT${NC}"
echo -e "${GRAY}  Node:    $ANT_NODE_DIR${NC}"
echo ""

# ── 1. Start ant devnet ──
echo -e "${YELLOW}[1/3] Starting ant devnet (25 nodes + EVM)...${NC}"
(cd "$ANT_NODE_DIR" && cargo run --release --bin ant-devnet -- --preset default --enable-evm --manifest "$MANIFEST_FILE" 2>&1) &
DEVNET_PID=$!

# ── 2. Wait for manifest ──
echo -e "${GRAY}       Waiting for devnet (first build may take several minutes)...${NC}"
BOOTSTRAP_PEERS=""
for i in $(seq 1 180); do
    sleep 2
    if [[ -f "$MANIFEST_FILE" ]]; then
        BOOTSTRAP_PEERS=$(python -c "
import json
try:
    m = json.load(open('$MANIFEST_FILE'))
    if m.get('bootstrap') and len(m['bootstrap']) > 0 and m.get('evm'):
        print(','.join(m['bootstrap']))
except Exception:
    pass
" 2>/dev/null) || true
        if [[ -n "$BOOTSTRAP_PEERS" ]]; then
            break
        fi
    fi
done

if [[ -z "$BOOTSTRAP_PEERS" ]]; then
    echo -e "${RED}       Timed out waiting for devnet manifest!${NC}"
    echo -e "${GRAY}       Check process output for errors.${NC}"
    exit 1
fi

# Extract EVM config from manifest
WALLET_KEY=$(python -c "
import json
m = json.load(open('$MANIFEST_FILE'))
k = m['evm']['wallet_private_key']
print(k[2:] if k.startswith('0x') else k)
" 2>/dev/null)

EVM_RPC_URL=$(python -c "import json; print(json.load(open('$MANIFEST_FILE'))['evm']['rpc_url'])" 2>/dev/null)
EVM_TOKEN_ADDR=$(python -c "import json; print(json.load(open('$MANIFEST_FILE'))['evm']['payment_token_address'])" 2>/dev/null)
EVM_VAULT_ADDR=$(python -c "import json; e=json.load(open('$MANIFEST_FILE'))['evm']; print(e.get('payment_vault_address', e.get('data_payments_address', '')))" 2>/dev/null)
NODE_COUNT=$(python -c "import json; print(json.load(open('$MANIFEST_FILE')).get('node_count', '?'))" 2>/dev/null)
BASE_PORT=$(python -c "import json; print(json.load(open('$MANIFEST_FILE')).get('base_port', '?'))" 2>/dev/null)

echo -e "${GREEN}       Devnet ready: $NODE_COUNT nodes, base port $BASE_PORT${NC}"
echo -e "${GREEN}       EVM:   $EVM_RPC_URL${NC}"

# ── 3. Start antd ──
echo -e "${YELLOW}[2/3] Starting antd...${NC}"
(cd "$ANTD_DIR" && \
    ANTD_PEERS="$BOOTSTRAP_PEERS" \
    AUTONOMI_WALLET_KEY="$WALLET_KEY" \
    EVM_RPC_URL="$EVM_RPC_URL" \
    EVM_PAYMENT_TOKEN_ADDRESS="$EVM_TOKEN_ADDR" \
    EVM_PAYMENT_VAULT_ADDRESS="$EVM_VAULT_ADDR" \
    cargo run -- --network local 2>&1) &
ANTD_PID=$!

# Save PIDs for kill script
PID_FILE="${TMPDIR:-/tmp}/antd-local-pids"
echo "$DEVNET_PID $ANTD_PID" > "$PID_FILE"

# ── 4. Wait for health ──
echo -e "${YELLOW}[3/3] Waiting for antd to be ready...${NC}"
READY=false
for i in $(seq 1 60); do
    sleep 3
    if curl -s http://localhost:8082/health 2>/dev/null | grep -q '"ok"'; then
        READY=true
        break
    fi
done

echo ""
if $READY; then
    echo -e "${GREEN}=== Ready! ===${NC}"
    echo ""
    echo -e "${WHITE}  REST:  http://localhost:8082${NC}"
    echo -e "${WHITE}  gRPC:  localhost:50051${NC}"
    echo -e "${WHITE}  Wallet: configured${NC}"
    echo ""
    echo -e "${GRAY}Run tests:${NC}"
    echo -e "${GRAY}  ./scripts/test-api.sh${NC}"
    echo ""
    echo -e "${GRAY}Tear down:${NC}"
    echo -e "${GRAY}  ./scripts/kill-local.sh${NC}"
else
    echo -e "${RED}=== antd did not respond within timeout ===${NC}"
    echo -e "${GRAY}Check process output for errors.${NC}"
fi
