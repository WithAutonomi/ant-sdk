package antd

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
)

// Pointers (antd >= 0.16.0): owner-signed, paid, mutable references. A
// pointer's address is derived from its owner's key and never changes; what
// it points at can be updated by the owner, and the owner can hand it over to
// another pointer for good (PointerTransfer).
//
// The daemon signs with owner keys it loaded at startup (--pointer-keys). A
// write names the pointer by its address (owner); PointerKeys lists the
// pointers the daemon can write.
//
// Every write pays, about the price of one chunk, and every attempt pays
// again: do not retry PointerCreate, PointerUpdate or PointerTransfer
// automatically. Reads are free to retry; a CloseGroupShortfallError on a
// read usually clears once an update in flight settles.

// PointerKeys returns the addresses of the pointers this daemon holds owner
// keys for. Only these can be written.
func (c *Client) PointerKeys(ctx context.Context) ([]string, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/pointers/keys", nil)
	if err != nil {
		return nil, err
	}
	var addresses []string
	for _, k := range arrAt(j, "keys") {
		if km, ok := k.(map[string]any); ok {
			addresses = append(addresses, str(km, "address"))
		}
	}
	return addresses, nil
}

// PointerCreate creates the pointer at owner, pointing at target, paid by the
// daemon wallet. kind defaults to PointerTargetChunk when empty. Returns an
// AlreadyExistsError, before paying, if the pointer exists.
func (c *Client) PointerCreate(ctx context.Context, owner, target string, kind PointerTargetKind) (*PointerWrite, error) {
	return c.pointerWrite(ctx, "/v1/pointers", owner, target, kind)
}

// PointerUpdate points the pointer at owner at target, paid by the daemon
// wallet, creating it if it does not exist. kind defaults to
// PointerTargetChunk when empty. Returns a PointerFinalError, before paying,
// if the pointer has been handed over or frozen.
func (c *Client) PointerUpdate(ctx context.Context, owner, target string, kind PointerTargetKind) (*PointerWrite, error) {
	return c.pointerWrite(ctx, "/v1/pointers/update", owner, target, kind)
}

func (c *Client) pointerWrite(ctx context.Context, path, owner, target string, kind PointerTargetKind) (*PointerWrite, error) {
	body := map[string]any{"owner": owner, "target": target}
	if kind != "" {
		body["kind"] = string(kind)
	}
	j, _, err := c.doJSON(ctx, http.MethodPost, path, body)
	if err != nil {
		return nil, err
	}
	return parsePointerWrite(j)
}

// PointerTransfer hands the pointer at owner over to the pointer at recipient,
// for good, paid by the daemon wallet. Readers of owner's address are
// redirected to the recipient's pointer, which only its owner can move.
// Irreversible once stored.
//
// Refused before paying if the pointer is already final (PointerFinalError),
// if recipient does not exist or leads back (BadRequestError), or if not every
// peer of the close group answered (CloseGroupShortfallError; retry later).
func (c *Client) PointerTransfer(ctx context.Context, owner, recipient string) (*PointerTransferResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/pointers/transfer", map[string]any{
		"owner":     owner,
		"recipient": recipient,
	})
	if err != nil {
		return nil, err
	}
	r := &PointerTransferResult{
		Address:       str(j, "address"),
		StateID:       str(j, "state_id"),
		FinalityError: str(j, "finality_error"),
	}
	if fm, ok := j["finality"].(map[string]any); ok {
		if r.Finality, err = parsePointerFinality(fm); err != nil {
			return nil, err
		}
	}
	return r, nil
}

// PointerGet reads the pointer at address. Returns a NotFoundError if no
// pointer exists there.
func (c *Client) PointerGet(ctx context.Context, address string) (*PointerRecord, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/pointers/"+address, nil)
	if err != nil {
		return nil, err
	}
	return parsePointerRecord(j)
}

// PointerResolve follows a chain of pointers from address to the target at its
// end (at most 16 hops). Returns a NotFoundError if a pointer on the chain does
// not exist.
func (c *Client) PointerResolve(ctx context.Context, address string) (*PointerTarget, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/pointers/"+address+"/resolve", nil)
	if err != nil {
		return nil, err
	}
	return &PointerTarget{
		Kind:    str(j, "kind"),
		KindTag: uint8(unum64(j, "kind_tag")),
		Target:  str(j, "target"),
	}, nil
}

// PointerFinality asks the whole close group where the pointer at address
// stands. Check it before relying on a transfer: only PointerFinal means the
// transfer is beyond dispute.
func (c *Client) PointerFinality(ctx context.Context, address string) (*PointerFinality, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/pointers/"+address+"/finality", nil)
	if err != nil {
		return nil, err
	}
	return parsePointerFinality(j)
}

// PointerController follows the transfers from address to the pointer whose
// owner now decides what it resolves to.
func (c *Client) PointerController(ctx context.Context, address string) (*PointerController, error) {
	j, _, err := c.doJSON(ctx, http.MethodGet, "/v1/pointers/"+address+"/controller", nil)
	if err != nil {
		return nil, err
	}
	r := &PointerController{
		Pointer:   str(j, "pointer"),
		Frozen:    boolField(j, "frozen"),
		Transfers: []string{},
	}
	for _, t := range arrAt(j, "transfers") {
		if s, ok := t.(string); ok {
			r.Transfers = append(r.Transfers, s)
		}
	}
	return r, nil
}

// PointerPrepare signs a pointer write with the daemon's loaded owner key and
// quotes it for an external signer, which pays with payForQuotes() and then
// calls PointerFinalize. The daemon needs no wallet. While the prepared write
// awaits payment, other writes to the same pointer return a ConflictError.
func (c *Client) PointerPrepare(ctx context.Context, req PointerPrepareRequest) (*PointerPrepareResult, error) {
	body := map[string]any{"owner": req.Owner, "op": string(req.Op)}
	if req.Target != "" {
		body["target"] = req.Target
	}
	if req.Kind != "" {
		body["kind"] = string(req.Kind)
	}
	if req.Recipient != "" {
		body["recipient"] = req.Recipient
	}
	if req.IncludeSignedQuotes {
		body["include_signed_quotes"] = true
	}
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/pointers/prepare", body)
	if err != nil {
		return nil, err
	}
	counter, err := pointerCounter(j, "counter")
	if err != nil {
		return nil, err
	}
	r := &PointerPrepareResult{
		UploadID:            str(j, "upload_id"),
		Op:                  PointerOp(str(j, "op")),
		Address:             str(j, "address"),
		StateID:             str(j, "state_id"),
		Counter:             counter,
		PaymentType:         str(j, "payment_type"),
		TotalAmount:         str(j, "total_amount"),
		PaymentVaultAddress: str(j, "payment_vault_address"),
		PaymentTokenAddress: str(j, "payment_token_address"),
		RPCUrl:              str(j, "rpc_url"),
		SignedQuotes:        parseSignedQuotes(arrAt(j, "signed_quotes")),
	}
	for _, p := range arrAt(j, "payments") {
		if pm, ok := p.(map[string]any); ok {
			r.Payments = append(r.Payments, PaymentInfo{
				QuoteHash:      str(pm, "quote_hash"),
				RewardsAddress: str(pm, "rewards_address"),
				Amount:         str(pm, "amount"),
			})
		}
	}
	return r, nil
}

// PointerFinalize stores a prepared pointer write once its external signer has
// paid. txHashes maps each quote_hash from PointerPrepare's Payments to the
// payForQuotes() transaction hash.
//
// A write that falls short after payment returns a CloseGroupShortfallError
// with Retryable set: the daemon kept the paid state, so call PointerFinalize
// again with the same uploadID (txHashes is then ignored) to store it against
// the same payment. Bound that loop; the session expires with the daemon's
// one-hour pending TTL.
func (c *Client) PointerFinalize(ctx context.Context, uploadID string, txHashes map[string]string) (*PointerFinalizeResult, error) {
	j, _, err := c.doJSON(ctx, http.MethodPost, "/v1/pointers/finalize", map[string]any{
		"upload_id": uploadID,
		"tx_hashes": txHashes,
	})
	if err != nil {
		return nil, err
	}
	counter, err := pointerCounter(j, "counter")
	if err != nil {
		return nil, err
	}
	r := &PointerFinalizeResult{
		Address: str(j, "address"),
		StateID: str(j, "state_id"),
		Counter: counter,
	}
	if fm, ok := j["finality"].(map[string]any); ok {
		if r.Finality, err = parsePointerFinality(fm); err != nil {
			return nil, err
		}
	}
	return r, nil
}

// pointerCounter parses a decimal counter. Counters travel as strings because
// a final state sits at 2^64-1, past what a JSON number keeps exactly in
// many languages.
func pointerCounter(m map[string]any, key string) (uint64, error) {
	s := str(m, key)
	n, err := strconv.ParseUint(s, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("antd: pointer %s %q is not a decimal counter", key, s)
	}
	return n, nil
}

func parsePointerWrite(j map[string]any) (*PointerWrite, error) {
	counter, err := pointerCounter(j, "counter")
	if err != nil {
		return nil, err
	}
	return &PointerWrite{Address: str(j, "address"), StateID: str(j, "state_id"), Counter: counter}, nil
}

func parsePointerRecord(j map[string]any) (*PointerRecord, error) {
	counter, err := pointerCounter(j, "counter")
	if err != nil {
		return nil, err
	}
	return &PointerRecord{
		Address:       str(j, "address"),
		Owner:         str(j, "owner"),
		Counter:       counter,
		Kind:          str(j, "kind"),
		KindTag:       uint8(unum64(j, "kind_tag")),
		Target:        str(j, "target"),
		StateID:       str(j, "state_id"),
		Final:         boolField(j, "is_final"),
		TransferredTo: str(j, "transferred_to"),
	}, nil
}

func parsePointerFinalState(m map[string]any) PointerFinalState {
	return PointerFinalState{
		StateID:       str(m, "state_id"),
		Kind:          str(m, "kind"),
		KindTag:       uint8(unum64(m, "kind_tag")),
		Target:        str(m, "target"),
		Holders:       uint32(unum64(m, "holders")),
		TransferredTo: str(m, "transferred_to"),
	}
}

func parsePointerFinality(j map[string]any) (*PointerFinality, error) {
	r := &PointerFinality{
		Address:       str(j, "address"),
		Group:         uint32(unum64(j, "group")),
		Answered:      uint32(unum64(j, "answered")),
		Status:        PointerFinalityStatus(str(j, "status")),
		TransferredTo: str(j, "transferred_to"),
	}
	if _, ok := j["counter"].(string); ok {
		counter, err := pointerCounter(j, "counter")
		if err != nil {
			return nil, err
		}
		r.Counter = &counter
	}
	if sm, ok := j["state"].(map[string]any); ok {
		state := parsePointerFinalState(sm)
		r.State = &state
	}
	for _, s := range arrAt(j, "states") {
		if sm, ok := s.(map[string]any); ok {
			r.States = append(r.States, parsePointerFinalState(sm))
		}
	}
	if mm, ok := j["majority"].(map[string]any); ok {
		majority := parsePointerFinalState(mm)
		r.Majority = &majority
	}
	return r, nil
}
