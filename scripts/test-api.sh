#!/usr/bin/env bash
set -uo pipefail

# ── REST API integration tests using only curl + jq ──
# Zero dependencies beyond standard Unix tools.
# Prerequisite: antd daemon running on local testnet.

BASE_URL="${ANTD_BASE_URL:-http://localhost:8080}"
PASS=0
FAIL=0

# ── Colors ──
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

# ── Helpers ──

b64encode() {
    # Base64-encode a string (no line wrapping)
    printf '%s' "$1" | base64 | tr -d '\n'
}

random_hex() {
    # Generate N random bytes as hex
    local n="${1:-32}"
    if command -v openssl &>/dev/null; then
        openssl rand -hex "$n"
    elif [[ -r /dev/urandom ]]; then
        dd if=/dev/urandom bs=1 count="$n" 2>/dev/null | xxd -p | tr -d '\n'
    else
        python3 -c "import os; print(os.urandom($n).hex())" 2>/dev/null || \
        python  -c "import os; print(os.urandom($n).hex())"
    fi
}

random_secret_key() {
    # BLS12-381 secret keys must be < the field modulus (~2^255).
    # Generate 32 random bytes, then zero the first and last bytes so the
    # 256-bit value fits regardless of endianness.
    local hex=$(random_hex 32)
    echo "00${hex:2:60}00"
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

assert_status() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}PASS${NC} $label (HTTP $actual)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label (expected HTTP $expected, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo -e "${CYAN}=== antd REST API Tests ===${NC}"
echo -e "${GRAY}Target: $BASE_URL${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════
# Test 01: Health Check
# ══════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}[01/10] Health Check${NC}"

RESP=$(curl -s "$BASE_URL/health")
STATUS=$(echo "$RESP" | jq -r '.status // empty')
NETWORK=$(echo "$RESP" | jq -r '.network // empty')

assert_eq "status is ok" "ok" "$STATUS"
assert_not_empty "network is set" "$NETWORK"
echo -e "       ${GRAY}Network: $NETWORK${NC}"

# ══════════════════════════════════════════════════════════════════════
# Test 02: Public Data — store, cost estimate, retrieve, round-trip
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[02/10] Public Data${NC}"

DATA_PAYLOAD="Hello, Autonomi network!"
DATA_B64=$(b64encode "$DATA_PAYLOAD")

# Cost estimate
COST_RESP=$(curl -s -X POST "$BASE_URL/v1/data/cost" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$DATA_B64\"}")
EST_COST=$(echo "$COST_RESP" | jq -r '.cost // empty')
assert_not_empty "cost estimate returned" "$EST_COST"
echo -e "       ${GRAY}Estimated cost: $EST_COST atto tokens${NC}"

# Store
PUT_RESP=$(curl -s -X POST "$BASE_URL/v1/data/public" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$DATA_B64\"}")
DATA_ADDR=$(echo "$PUT_RESP" | jq -r '.address // empty')
DATA_COST=$(echo "$PUT_RESP" | jq -r '.cost // empty')
assert_not_empty "data address returned" "$DATA_ADDR"
assert_not_empty "data cost returned" "$DATA_COST"
echo -e "       ${GRAY}Address: ${DATA_ADDR:0:16}...${NC}"

# Retrieve
GET_RESP=$(curl -s "$BASE_URL/v1/data/public/$DATA_ADDR")
GOT_B64=$(echo "$GET_RESP" | jq -r '.data // empty')
GOT_TEXT=$(echo "$GOT_B64" | base64 -d 2>/dev/null)
assert_eq "round-trip matches" "$DATA_PAYLOAD" "$GOT_TEXT"

# ══════════════════════════════════════════════════════════════════════
# Test 03: Raw Chunks — store and retrieve
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[03/10] Chunks${NC}"

CHUNK_PAYLOAD="Raw chunk content for direct storage"
CHUNK_B64=$(b64encode "$CHUNK_PAYLOAD")

# Store
CHUNK_PUT=$(curl -s -X POST "$BASE_URL/v1/chunks" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$CHUNK_B64\"}")
CHUNK_ADDR=$(echo "$CHUNK_PUT" | jq -r '.address // empty')
CHUNK_COST=$(echo "$CHUNK_PUT" | jq -r '.cost // empty')
assert_not_empty "chunk address returned" "$CHUNK_ADDR"
assert_not_empty "chunk cost returned" "$CHUNK_COST"

# Retrieve
CHUNK_GET=$(curl -s "$BASE_URL/v1/chunks/$CHUNK_ADDR")
CHUNK_GOT=$(echo "$CHUNK_GET" | jq -r '.data // empty' | base64 -d 2>/dev/null)
assert_eq "chunk round-trip matches" "$CHUNK_PAYLOAD" "$CHUNK_GOT"

# ══════════════════════════════════════════════════════════════════════
# Test 04: Files — upload and download
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[04/10] Files${NC}"

SRC_FILE=$(mktemp)
echo -n "Hello from a file on Autonomi!" > "$SRC_FILE"

# Cost estimate
FILE_COST_RESP=$(curl -s -X POST "$BASE_URL/v1/cost/file" \
    -H "Content-Type: application/json" \
    -d "{\"path\": \"$SRC_FILE\", \"is_public\": true, \"include_archive\": false}")
FILE_EST=$(echo "$FILE_COST_RESP" | jq -r '.cost // empty')
assert_not_empty "file cost estimate returned" "$FILE_EST"

# Upload
FILE_UP=$(curl -s -X POST "$BASE_URL/v1/files/upload/public" \
    -H "Content-Type: application/json" \
    -d "{\"path\": \"$SRC_FILE\"}")
FILE_ADDR=$(echo "$FILE_UP" | jq -r '.address // empty')
FILE_COST=$(echo "$FILE_UP" | jq -r '.cost // empty')
assert_not_empty "file address returned" "$FILE_ADDR"
assert_not_empty "file upload cost returned" "$FILE_COST"

# Download
DEST_FILE="${SRC_FILE}.downloaded"
DL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/v1/files/download/public" \
    -H "Content-Type: application/json" \
    -d "{\"address\": \"$FILE_ADDR\", \"dest_path\": \"$DEST_FILE\"}")
assert_status "file download succeeded" "200" "$DL_STATUS"

if [[ -f "$DEST_FILE" ]]; then
    DL_CONTENT=$(cat "$DEST_FILE")
    assert_eq "file content matches" "Hello from a file on Autonomi!" "$DL_CONTENT"
    rm -f "$DEST_FILE"
else
    echo -e "  ${RED}FAIL${NC} downloaded file not found"
    FAIL=$((FAIL + 1))
fi
rm -f "$SRC_FILE"

# ══════════════════════════════════════════════════════════════════════
# Test 05: Pointers — create, read, exists, update
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[05/10] Pointers${NC}"

PTR_KEY=$(random_secret_key)

# Store two data versions to point to
V1_B64=$(b64encode "version 1")
V2_B64=$(b64encode "version 2")

V1_RESP=$(curl -s -X POST "$BASE_URL/v1/data/public" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$V1_B64\"}")
V1_ADDR=$(echo "$V1_RESP" | jq -r '.address')

V2_RESP=$(curl -s -X POST "$BASE_URL/v1/data/public" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$V2_B64\"}")
V2_ADDR=$(echo "$V2_RESP" | jq -r '.address')

# Create pointer to v1
PTR_CREATE=$(curl -s -X POST "$BASE_URL/v1/pointers" \
    -H "Content-Type: application/json" \
    -d "{\"owner_secret_key\": \"$PTR_KEY\", \"target\": {\"kind\": \"chunk\", \"address\": \"$V1_ADDR\"}}")
PTR_ADDR=$(echo "$PTR_CREATE" | jq -r '.address // empty')
PTR_COST=$(echo "$PTR_CREATE" | jq -r '.cost // empty')
assert_not_empty "pointer address returned" "$PTR_ADDR"
assert_not_empty "pointer cost returned" "$PTR_COST"

# Read pointer
PTR_GET=$(curl -s "$BASE_URL/v1/pointers/$PTR_ADDR")
PTR_TARGET=$(echo "$PTR_GET" | jq -r '.target.address // empty')
PTR_KIND=$(echo "$PTR_GET" | jq -r '.target.kind // empty')
PTR_COUNTER=$(echo "$PTR_GET" | jq -r '.counter // empty')
assert_eq "pointer target is v1" "$V1_ADDR" "$PTR_TARGET"
assert_eq "pointer kind is chunk" "chunk" "$PTR_KIND"
assert_not_empty "pointer counter returned" "$PTR_COUNTER"

# Check existence
EXISTS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -I "$BASE_URL/v1/pointers/$PTR_ADDR")
assert_status "pointer exists (HEAD)" "200" "$EXISTS_STATUS"

# Update to v2
UPD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$BASE_URL/v1/pointers/$PTR_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"owner_secret_key\": \"$PTR_KEY\", \"target\": {\"kind\": \"chunk\", \"address\": \"$V2_ADDR\"}}")
assert_status "pointer update succeeded" "200" "$UPD_STATUS"

# Read again — should point to v2
PTR_GET2=$(curl -s "$BASE_URL/v1/pointers/$PTR_ADDR")
PTR_TARGET2=$(echo "$PTR_GET2" | jq -r '.target.address // empty')
assert_eq "pointer now targets v2" "$V2_ADDR" "$PTR_TARGET2"

# ══════════════════════════════════════════════════════════════════════
# Test 06: Scratchpads — create, read, exists, update
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[06/10] Scratchpads${NC}"

PAD_KEY=$(random_secret_key)
PAD_DATA_V1=$(b64encode "scratchpad v1 data")
PAD_DATA_V2=$(b64encode "scratchpad v2 data")

# Create
PAD_CREATE=$(curl -s -X POST "$BASE_URL/v1/scratchpads" \
    -H "Content-Type: application/json" \
    -d "{\"owner_secret_key\": \"$PAD_KEY\", \"content_type\": 1, \"data\": \"$PAD_DATA_V1\"}")
PAD_ADDR=$(echo "$PAD_CREATE" | jq -r '.address // empty')
PAD_COST=$(echo "$PAD_CREATE" | jq -r '.cost // empty')
assert_not_empty "scratchpad address returned" "$PAD_ADDR"
assert_not_empty "scratchpad cost returned" "$PAD_COST"

# Read
PAD_GET=$(curl -s "$BASE_URL/v1/scratchpads/$PAD_ADDR")
PAD_COUNTER=$(echo "$PAD_GET" | jq -r '.counter // empty')
PAD_ENCODING=$(echo "$PAD_GET" | jq -r '.data_encoding // empty')
assert_not_empty "scratchpad counter returned" "$PAD_COUNTER"
assert_not_empty "scratchpad data_encoding returned" "$PAD_ENCODING"

# Check existence
PAD_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" -I "$BASE_URL/v1/scratchpads/$PAD_ADDR")
assert_status "scratchpad exists (HEAD)" "200" "$PAD_EXISTS"

# Update
PAD_UPD=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$BASE_URL/v1/scratchpads/$PAD_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"owner_secret_key\": \"$PAD_KEY\", \"content_type\": 1, \"data\": \"$PAD_DATA_V2\"}")
assert_status "scratchpad update succeeded" "200" "$PAD_UPD"

# Read again — counter should have incremented
PAD_GET2=$(curl -s "$BASE_URL/v1/scratchpads/$PAD_ADDR")
PAD_COUNTER2=$(echo "$PAD_GET2" | jq -r '.counter // empty')
assert_not_empty "scratchpad counter after update" "$PAD_COUNTER2"
echo -e "       ${GRAY}Counter: $PAD_COUNTER -> $PAD_COUNTER2${NC}"

# ══════════════════════════════════════════════════════════════════════
# Test 07: Graph Entries — create, read, exists, cost
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[07/10] Graph Entries${NC}"

GRAPH_KEY=$(random_secret_key)
GRAPH_CONTENT=$(random_hex 32)

# Create root entry (no parents, no descendants)
GRAPH_CREATE=$(curl -s -X POST "$BASE_URL/v1/graph" \
    -H "Content-Type: application/json" \
    -d "{\"owner_secret_key\": \"$GRAPH_KEY\", \"parents\": [], \"content\": \"$GRAPH_CONTENT\", \"descendants\": []}")
GRAPH_ADDR=$(echo "$GRAPH_CREATE" | jq -r '.address // empty')
GRAPH_COST=$(echo "$GRAPH_CREATE" | jq -r '.cost // empty')
assert_not_empty "graph entry address returned" "$GRAPH_ADDR"
assert_not_empty "graph entry cost returned" "$GRAPH_COST"

# Read
GRAPH_GET=$(curl -s "$BASE_URL/v1/graph/$GRAPH_ADDR")
GRAPH_OWNER=$(echo "$GRAPH_GET" | jq -r '.owner // empty')
GRAPH_GOT_CONTENT=$(echo "$GRAPH_GET" | jq -r '.content // empty')
GRAPH_PARENTS=$(echo "$GRAPH_GET" | jq -r '.parents | length')
assert_not_empty "graph entry owner returned" "$GRAPH_OWNER"
assert_eq "graph entry content matches" "$GRAPH_CONTENT" "$GRAPH_GOT_CONTENT"
assert_eq "graph entry has 0 parents" "0" "$GRAPH_PARENTS"

# Check existence
GRAPH_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" -I "$BASE_URL/v1/graph/$GRAPH_ADDR")
assert_status "graph entry exists (HEAD)" "200" "$GRAPH_EXISTS"

# Cost estimate (uses the owner public key from the GET response)
GRAPH_COST_RESP=$(curl -s -X POST "$BASE_URL/v1/graph/cost" \
    -H "Content-Type: application/json" \
    -d "{\"public_key\": \"$GRAPH_OWNER\"}")
GRAPH_EST=$(echo "$GRAPH_COST_RESP" | jq -r '.cost // empty')
assert_not_empty "graph entry cost estimate returned" "$GRAPH_EST"

# ══════════════════════════════════════════════════════════════════════
# Test 08: Registers — create, read, update
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[08/10] Registers${NC}"

REG_KEY=$(random_secret_key)
REG_INITIAL=$(printf '0%.0s' $(seq 1 64))  # 64 hex zeros = 32 zero bytes
REG_NEW_VALUE=$(random_hex 32)

# Create
REG_CREATE=$(curl -s -X POST "$BASE_URL/v1/registers" \
    -H "Content-Type: application/json" \
    -d "{\"owner_secret_key\": \"$REG_KEY\", \"initial_value\": \"$REG_INITIAL\"}")
REG_ADDR=$(echo "$REG_CREATE" | jq -r '.address // empty')
REG_COST=$(echo "$REG_CREATE" | jq -r '.cost // empty')
assert_not_empty "register address returned" "$REG_ADDR"
assert_not_empty "register cost returned" "$REG_COST"

# Read
REG_GET=$(curl -s "$BASE_URL/v1/registers/$REG_ADDR")
REG_VALUE=$(echo "$REG_GET" | jq -r '.value // empty')
assert_eq "register initial value matches" "$REG_INITIAL" "$REG_VALUE"

# Update
REG_UPD=$(curl -s -X PUT "$BASE_URL/v1/registers/$REG_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"owner_secret_key\": \"$REG_KEY\", \"new_value\": \"$REG_NEW_VALUE\"}")
REG_UPD_COST=$(echo "$REG_UPD" | jq -r '.cost // empty')
assert_not_empty "register update cost returned" "$REG_UPD_COST"

# Read again
REG_GET2=$(curl -s "$BASE_URL/v1/registers/$REG_ADDR")
REG_VALUE2=$(echo "$REG_GET2" | jq -r '.value // empty')
assert_eq "register updated value matches" "$REG_NEW_VALUE" "$REG_VALUE2"

# ══════════════════════════════════════════════════════════════════════
# Test 09: Vaults — store and retrieve
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[09/10] Vaults${NC}"

VAULT_KEY=$(random_secret_key)
VAULT_PAYLOAD="Secret vault data that is encrypted"
VAULT_B64=$(b64encode "$VAULT_PAYLOAD")
VAULT_CONTENT_TYPE=42

# Store
VAULT_PUT=$(curl -s -X POST "$BASE_URL/v1/vaults" \
    -H "Content-Type: application/json" \
    -d "{\"secret_key\": \"$VAULT_KEY\", \"data\": \"$VAULT_B64\", \"content_type\": $VAULT_CONTENT_TYPE}")
VAULT_COST=$(echo "$VAULT_PUT" | jq -r '.cost // empty')
assert_not_empty "vault store cost returned" "$VAULT_COST"

# Retrieve
VAULT_GET=$(curl -s "$BASE_URL/v1/vaults?secret_key=$VAULT_KEY")
VAULT_GOT_B64=$(echo "$VAULT_GET" | jq -r '.data // empty')
VAULT_GOT_CT=$(echo "$VAULT_GET" | jq -r '.content_type // empty')
VAULT_GOT_TEXT=$(echo "$VAULT_GOT_B64" | base64 -d 2>/dev/null)
assert_eq "vault data round-trip matches" "$VAULT_PAYLOAD" "$VAULT_GOT_TEXT"
assert_eq "vault content_type matches" "$VAULT_CONTENT_TYPE" "$VAULT_GOT_CT"

# ══════════════════════════════════════════════════════════════════════
# Test 10: Private Data — store and retrieve
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YELLOW}[10/10] Private Data${NC}"

PRIV_PAYLOAD="This message is encrypted on the network"
PRIV_B64=$(b64encode "$PRIV_PAYLOAD")

# Store private
PRIV_PUT=$(curl -s -X POST "$BASE_URL/v1/data/private" \
    -H "Content-Type: application/json" \
    -d "{\"data\": \"$PRIV_B64\"}")
DATA_MAP=$(echo "$PRIV_PUT" | jq -r '.data_map // empty')
PRIV_COST=$(echo "$PRIV_PUT" | jq -r '.cost // empty')
assert_not_empty "private data map returned" "$DATA_MAP"
assert_not_empty "private data cost returned" "$PRIV_COST"

# Retrieve and decrypt
PRIV_GET=$(curl -s "$BASE_URL/v1/data/private?data_map=$DATA_MAP")
PRIV_GOT_B64=$(echo "$PRIV_GET" | jq -r '.data // empty')
PRIV_GOT_TEXT=$(echo "$PRIV_GOT_B64" | base64 -d 2>/dev/null)
assert_eq "private data round-trip matches" "$PRIV_PAYLOAD" "$PRIV_GOT_TEXT"

# ══════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}=== Results ===${NC}"
TOTAL=$((PASS + FAIL))
echo -e "  ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} out of $TOTAL assertions"
echo ""

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
