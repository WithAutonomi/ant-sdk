#!/usr/bin/env bash
set -uo pipefail

## REST API integration tests using curl + jq.
##
## Prerequisites:
##   - curl
##   - jq (https://jqlang.github.io/jq/ — install via: apt install jq / brew install jq / choco install jq)
##   - antd running on local testnet with wallet configured (./scripts/start-local.sh)

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
    local label="$1" reason="${2:-not available}"
    echo -e "  ${DARKYELLOW}SKIP${NC} $label ($reason)"
    SKIP=$((SKIP + 1))
}

echo ""
echo -e "${CYAN}=== antd REST API Tests ===${NC}"
echo -e "${GRAY}Target: $BASE_URL${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════
# Test 01: Health Check
# ══════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[01/06] Health Check${NC}"

RESP=$(curl -s "$BASE_URL/health")
STATUS=$(echo "$RESP" | jq -r '.status // empty')
NETWORK=$(echo "$RESP" | jq -r '.network // empty')

assert_eq "status is ok" "ok" "$STATUS"
assert_not_empty "network is set" "$NETWORK"
echo -e "       ${GRAY}Network: $NETWORK${NC}"

# ══════════════════════════════════════════════════════════════════════
# Test 02: Public Data — put + get roundtrip
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[02/06] Public Data${NC}"

DATA_PAYLOAD="Public data payload for roundtrip"
DATA_B64=$(b64encode "$DATA_PAYLOAD")

DATA_PUT=$(curl -s -X POST "$BASE_URL/v1/data/public" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$DATA_B64\"}")
DATA_ADDR=$(echo "$DATA_PUT" | jq -r '.address // empty')
DATA_CHUNKS=$(echo "$DATA_PUT" | jq -r '.chunks_stored // empty')
DATA_MODE=$(echo "$DATA_PUT" | jq -r '.payment_mode_used // empty')

if [[ -z "$DATA_ADDR" ]]; then
    DATA_ERR=$(echo "$DATA_PUT" | jq -r '.error // empty')
    echo -e "  ${RED}FAIL${NC} data PUT failed: $DATA_ERR"
    FAIL=$((FAIL + 4))
else
    assert_not_empty "data address returned" "$DATA_ADDR"
    assert_not_empty "chunks_stored returned" "$DATA_CHUNKS"
    assert_not_empty "payment_mode_used returned" "$DATA_MODE"
    echo -e "       ${GRAY}Address: ${DATA_ADDR:0:16}...  Chunks: $DATA_CHUNKS  Mode: $DATA_MODE${NC}"

    DATA_GET=$(curl -s "$BASE_URL/v1/data/public/$DATA_ADDR")
    DATA_GOT=$(echo "$DATA_GET" | jq -r '.data // empty' | base64 -d 2>/dev/null)
    assert_eq "data round-trip matches" "$DATA_PAYLOAD" "$DATA_GOT"
fi

# ══════════════════════════════════════════════════════════════════════
# Test 03: Raw Chunks — store and retrieve
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[03/06] Chunks${NC}"

CHUNK_PAYLOAD="Raw chunk content for direct storage"
CHUNK_B64=$(b64encode "$CHUNK_PAYLOAD")

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

    CHUNK_GET=$(curl -s "$BASE_URL/v1/chunks/$CHUNK_ADDR")
    CHUNK_GOT=$(echo "$CHUNK_GET" | jq -r '.data // empty' | base64 -d 2>/dev/null)
    assert_eq "chunk round-trip matches" "$CHUNK_PAYLOAD" "$CHUNK_GOT"
fi

# ══════════════════════════════════════════════════════════════════════
# Test 04: Files — upload + download roundtrip
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[04/06] Files${NC}"

FILE_PAYLOAD="File contents for upload roundtrip $(date +%s)"
TMP_SRC=$(mktemp)
TMP_DST="${TMP_SRC}.downloaded"
printf '%s' "$FILE_PAYLOAD" > "$TMP_SRC"

FILE_PUT=$(curl -s -X POST "$BASE_URL/v1/files/upload/public" \
    -H "Content-Type: application/json" \
    -d "{\"path\": \"$TMP_SRC\"}")
FILE_ADDR=$(echo "$FILE_PUT" | jq -r '.address // empty')
FILE_STORAGE=$(echo "$FILE_PUT" | jq -r '.storage_cost_atto // empty')
FILE_GAS=$(echo "$FILE_PUT" | jq -r '.gas_cost_wei // empty')
FILE_CHUNKS=$(echo "$FILE_PUT" | jq -r '.chunks_stored // empty')
FILE_MODE=$(echo "$FILE_PUT" | jq -r '.payment_mode_used // empty')

if [[ -z "$FILE_ADDR" ]]; then
    FILE_ERR=$(echo "$FILE_PUT" | jq -r '.error // empty')
    echo -e "  ${RED}FAIL${NC} file upload failed: $FILE_ERR"
    FAIL=$((FAIL + 6))
else
    assert_not_empty "file address returned" "$FILE_ADDR"
    assert_not_empty "storage_cost_atto returned" "$FILE_STORAGE"
    assert_not_empty "gas_cost_wei returned" "$FILE_GAS"
    assert_not_empty "chunks_stored returned" "$FILE_CHUNKS"
    assert_not_empty "payment_mode_used returned" "$FILE_MODE"
    echo -e "       ${GRAY}Address: ${FILE_ADDR:0:16}...  Storage: $FILE_STORAGE  Gas: $FILE_GAS  Chunks: $FILE_CHUNKS${NC}"

    DL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/v1/files/download/public" \
        -H "Content-Type: application/json" \
        -d "{\"address\": \"$FILE_ADDR\", \"dest_path\": \"$TMP_DST\"}")
    assert_eq "file download status 200" "200" "$DL_STATUS"

    if [[ -f "$TMP_DST" ]]; then
        FILE_GOT=$(cat "$TMP_DST")
        assert_eq "file round-trip matches" "$FILE_PAYLOAD" "$FILE_GOT"
    else
        echo -e "  ${RED}FAIL${NC} downloaded file not written to $TMP_DST"
        FAIL=$((FAIL + 1))
    fi
fi

rm -f "$TMP_SRC" "$TMP_DST"

# ══════════════════════════════════════════════════════════════════════
# Test 05: Private Data — put + get roundtrip
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[05/06] Private Data${NC}"

PRIV_PAYLOAD="Encrypted secret payload"
PRIV_B64=$(b64encode "$PRIV_PAYLOAD")

PRIV_PUT=$(curl -s -X POST "$BASE_URL/v1/data/private" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$PRIV_B64\"}")
PRIV_MAP=$(echo "$PRIV_PUT" | jq -r '.data_map // empty')
PRIV_CHUNKS=$(echo "$PRIV_PUT" | jq -r '.chunks_stored // empty')
PRIV_MODE=$(echo "$PRIV_PUT" | jq -r '.payment_mode_used // empty')

if [[ -z "$PRIV_MAP" ]]; then
    PRIV_ERR=$(echo "$PRIV_PUT" | jq -r '.error // empty')
    echo -e "  ${RED}FAIL${NC} private PUT failed: $PRIV_ERR"
    FAIL=$((FAIL + 4))
else
    assert_not_empty "data_map returned" "$PRIV_MAP"
    assert_not_empty "chunks_stored returned" "$PRIV_CHUNKS"
    assert_not_empty "payment_mode_used returned" "$PRIV_MODE"
    echo -e "       ${GRAY}DataMap: ${PRIV_MAP:0:16}...  Chunks: $PRIV_CHUNKS  Mode: $PRIV_MODE${NC}"

    PRIV_GET=$(curl -s -G "$BASE_URL/v1/data/private" --data-urlencode "data_map=$PRIV_MAP")
    PRIV_GOT=$(echo "$PRIV_GET" | jq -r '.data // empty' | base64 -d 2>/dev/null)
    assert_eq "private round-trip matches" "$PRIV_PAYLOAD" "$PRIV_GOT"
fi

# ══════════════════════════════════════════════════════════════════════
# Test 06: Cost estimation (data + file)
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[06/06] Cost estimation${NC}"

COST_PAYLOAD="Cost estimation payload"
COST_B64=$(b64encode "$COST_PAYLOAD")

DATA_COST=$(curl -s -X POST "$BASE_URL/v1/data/cost" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$COST_B64\"}")
DC_COST=$(echo "$DATA_COST" | jq -r '.cost // empty')
DC_SIZE=$(echo "$DATA_COST" | jq -r '.file_size // empty')
DC_CHUNKS=$(echo "$DATA_COST" | jq -r '.chunk_count // empty')
DC_GAS=$(echo "$DATA_COST" | jq -r '.estimated_gas_cost_wei // empty')
DC_MODE=$(echo "$DATA_COST" | jq -r '.payment_mode // empty')

if [[ -z "$DC_COST" ]]; then
    DC_ERR=$(echo "$DATA_COST" | jq -r '.error // empty')
    echo -e "  ${RED}FAIL${NC} /v1/data/cost failed: $DC_ERR"
    FAIL=$((FAIL + 5))
else
    assert_not_empty "data cost returned" "$DC_COST"
    assert_not_empty "data file_size returned" "$DC_SIZE"
    assert_not_empty "data chunk_count returned" "$DC_CHUNKS"
    assert_not_empty "data estimated_gas_cost_wei returned" "$DC_GAS"
    assert_not_empty "data payment_mode returned" "$DC_MODE"
    echo -e "       ${GRAY}Cost: $DC_COST  Size: $DC_SIZE  Chunks: $DC_CHUNKS  Gas: $DC_GAS  Mode: $DC_MODE${NC}"
fi

TMP_COST=$(mktemp)
printf '%s' "$COST_PAYLOAD extra content for file sampling" > "$TMP_COST"

FILE_COST=$(curl -s -X POST "$BASE_URL/v1/files/cost" \
    -H "Content-Type: application/json" \
    -d "{\"path\": \"$TMP_COST\", \"is_public\": true}")
FC_COST=$(echo "$FILE_COST" | jq -r '.cost // empty')
FC_SIZE=$(echo "$FILE_COST" | jq -r '.file_size // empty')
FC_CHUNKS=$(echo "$FILE_COST" | jq -r '.chunk_count // empty')
FC_GAS=$(echo "$FILE_COST" | jq -r '.estimated_gas_cost_wei // empty')
FC_MODE=$(echo "$FILE_COST" | jq -r '.payment_mode // empty')

if [[ -z "$FC_COST" ]]; then
    FC_ERR=$(echo "$FILE_COST" | jq -r '.error // empty')
    echo -e "  ${RED}FAIL${NC} /v1/files/cost failed: $FC_ERR"
    FAIL=$((FAIL + 5))
else
    assert_not_empty "file cost returned" "$FC_COST"
    assert_not_empty "file file_size returned" "$FC_SIZE"
    assert_not_empty "file chunk_count returned" "$FC_CHUNKS"
    assert_not_empty "file estimated_gas_cost_wei returned" "$FC_GAS"
    assert_not_empty "file payment_mode returned" "$FC_MODE"
    echo -e "       ${GRAY}Cost: $FC_COST  Size: $FC_SIZE  Chunks: $FC_CHUNKS  Gas: $FC_GAS  Mode: $FC_MODE${NC}"
fi

rm -f "$TMP_COST"

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
