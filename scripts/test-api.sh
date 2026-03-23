#!/usr/bin/env bash
set -uo pipefail

## REST API integration tests using only curl + jq.
## Zero dependencies beyond standard Unix tools.
##
## Prerequisite: antd running on local testnet (./scripts/start-local.sh)
##
## Currently tests health + chunks (working with ant-node).
## Data, files, graph, and private data are not yet implemented.

BASE_URL="${ANTD_BASE_URL:-http://localhost:8082}"
PASS=0
FAIL=0
SKIP=0

# ── Colors ──
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;90m'
DARKYELLOW='\033[0;33m'
NC='\033[0m'

# ── Helpers ──

b64encode() {
    printf '%s' "$1" | base64 | tr -d '\n'
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}PASS${NC} $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label"
        echo -e "       ${GRAY}expected: $expected${NC}"
        echo -e "       ${GRAY}actual:   $actual${NC}"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_empty() {
    local label="$1" value="$2"
    if [[ -n "$value" && "$value" != "null" ]]; then
        echo -e "  ${GREEN}PASS${NC} $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label (empty or null)"
        FAIL=$((FAIL + 1))
    fi
}

skip_test() {
    local label="$1"
    echo -e "  ${DARKYELLOW}SKIP${NC} $label (not yet implemented for ant-node)"
    SKIP=$((SKIP + 1))
}

echo ""
echo -e "${CYAN}=== antd REST API Tests ===${NC}"
echo -e "${GRAY}Target: $BASE_URL${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════
# Test 01: Health Check
# ══════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[01/07] Health Check${NC}"

RESP=$(curl -s "$BASE_URL/health")
STATUS=$(echo "$RESP" | jq -r '.status // empty')
NETWORK=$(echo "$RESP" | jq -r '.network // empty')

assert_eq "status is ok" "ok" "$STATUS"
assert_not_empty "network is set" "$NETWORK"
echo -e "       ${GRAY}Network: $NETWORK${NC}"

# ══════════════════════════════════════════════════════════════════════
# Test 02: Public Data (SKIPPED)
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[02/07] Public Data${NC}"
skip_test "public data put/get/cost"

# ══════════════════════════════════════════════════════════════════════
# Test 03: Raw Chunks — store and retrieve
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[03/07] Chunks${NC}"

CHUNK_PAYLOAD="Raw chunk content for direct storage"
CHUNK_B64=$(b64encode "$CHUNK_PAYLOAD")

# Store
CHUNK_PUT=$(curl -s -X POST "$BASE_URL/v1/chunks" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$CHUNK_B64\"}")
CHUNK_ADDR=$(echo "$CHUNK_PUT" | jq -r '.address // empty')
CHUNK_COST=$(echo "$CHUNK_PUT" | jq -r '.cost // empty')

if [[ -z "$CHUNK_ADDR" ]]; then
    CHUNK_ERR=$(echo "$CHUNK_PUT" | jq -r '.error // empty')
    echo -e "  ${RED}FAIL${NC} chunk PUT failed: $CHUNK_ERR"
    FAIL=$((FAIL + 3))
else
    assert_not_empty "chunk address returned" "$CHUNK_ADDR"
    assert_not_empty "chunk cost returned" "$CHUNK_COST"
    echo -e "       ${GRAY}Address: ${CHUNK_ADDR:0:16}...  Cost: $CHUNK_COST${NC}"

    # Retrieve
    CHUNK_GET=$(curl -s "$BASE_URL/v1/chunks/$CHUNK_ADDR")
    CHUNK_GOT=$(echo "$CHUNK_GET" | jq -r '.data // empty' | base64 -d 2>/dev/null)
    assert_eq "chunk round-trip matches" "$CHUNK_PAYLOAD" "$CHUNK_GOT"
fi

# ══════════════════════════════════════════════════════════════════════
# Test 04: Files (SKIPPED)
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[04/07] Files${NC}"
skip_test "file upload/download/cost"

# ══════════════════════════════════════════════════════════════════════
# Test 05: Graph Entries (SKIPPED)
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[05/07] Graph Entries${NC}"
skip_test "graph entry put/get/exists/cost"

# ══════════════════════════════════════════════════════════════════════
# Test 06: Private Data (SKIPPED)
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[06/07] Private Data${NC}"
skip_test "private data put/get"

# ══════════════════════════════════════════════════════════════════════
# Test 07: Wallet
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[07/07] Wallet${NC}"

WALLET_ADDR=$(curl -s "$BASE_URL/v1/wallet/address")
ADDR_VAL=$(echo "$WALLET_ADDR" | jq -r '.address // empty')
assert_not_empty "wallet address returned" "$ADDR_VAL"
if [[ -n "$ADDR_VAL" ]]; then
    echo -e "       ${GRAY}Address: $ADDR_VAL${NC}"
fi

WALLET_BAL=$(curl -s "$BASE_URL/v1/wallet/balance")
TOKEN_BAL=$(echo "$WALLET_BAL" | jq -r '.balance // empty')
GAS_BAL=$(echo "$WALLET_BAL" | jq -r '.gas_balance // empty')
assert_not_empty "token balance returned" "$TOKEN_BAL"
assert_not_empty "gas balance returned" "$GAS_BAL"
if [[ -n "$TOKEN_BAL" ]]; then
    echo -e "       ${GRAY}Tokens: $TOKEN_BAL atto${NC}"
    echo -e "       ${GRAY}Gas:    $GAS_BAL wei${NC}"
fi

# ══════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}=== Results ===${NC}"
TOTAL=$((PASS + FAIL))
echo -e "  ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${DARKYELLOW}$SKIP skipped${NC} out of $((TOTAL + SKIP)) tests"
echo ""

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
