package antd

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

// pointerDaemon serves canned /v1/pointers responses and records the last
// request body it was sent.
func pointerDaemon(t *testing.T, routes map[string]func(body map[string]any) (int, any)) (*Client, *map[string]any) {
	t.Helper()
	var last map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		last = nil
		if r.Body != nil {
			_ = json.NewDecoder(r.Body).Decode(&last)
		}
		route, ok := routes[r.Method+" "+r.URL.Path]
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			writeJSON(w, map[string]any{"error": "no route " + r.URL.Path, "code": "NOT_FOUND"})
			return
		}
		status, body := route(last)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		writeJSON(w, body)
	}))
	t.Cleanup(srv.Close)
	return NewClient(srv.URL), &last
}

func reply(status int, body any) func(map[string]any) (int, any) {
	return func(map[string]any) (int, any) { return status, body }
}

func TestPointerKeys(t *testing.T) {
	c, _ := pointerDaemon(t, map[string]func(map[string]any) (int, any){
		"GET /v1/pointers/keys": reply(200, map[string]any{"keys": []any{
			map[string]any{"address": "aa"}, map[string]any{"address": "bb"},
		}}),
	})
	keys, err := c.PointerKeys(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(keys) != 2 || keys[0] != "aa" || keys[1] != "bb" {
		t.Fatalf("keys = %v", keys)
	}
}

func TestPointerCreateAndUpdateSendOwnerTargetKind(t *testing.T) {
	write := reply(200, map[string]any{"address": "aa", "state_id": "ss", "counter": "7"})
	c, last := pointerDaemon(t, map[string]func(map[string]any) (int, any){
		"POST /v1/pointers":        write,
		"POST /v1/pointers/update": write,
	})

	w, err := c.PointerCreate(context.Background(), "aa", "tt", "")
	if err != nil {
		t.Fatal(err)
	}
	if w.Address != "aa" || w.StateID != "ss" || w.Counter != 7 {
		t.Fatalf("write = %+v", w)
	}
	if (*last)["owner"] != "aa" || (*last)["target"] != "tt" {
		t.Fatalf("body = %v", *last)
	}
	if _, sent := (*last)["kind"]; sent {
		t.Fatalf("an empty kind must be left to the daemon's default, sent %v", *last)
	}

	if _, err := c.PointerUpdate(context.Background(), "aa", "bb", PointerTargetPointer); err != nil {
		t.Fatal(err)
	}
	if (*last)["kind"] != "pointer" {
		t.Fatalf("body = %v", *last)
	}
}

func TestPointerGetReadsTheFinalCounterExactly(t *testing.T) {
	c, _ := pointerDaemon(t, map[string]func(map[string]any) (int, any){
		"GET /v1/pointers/aa": reply(200, map[string]any{
			"address": "aa", "owner": "pk", "counter": "18446744073709551615",
			"kind": "pointer", "kind_tag": 1, "target": "bb", "state_id": "ss",
			"is_final": true, "transferred_to": "bb",
		}),
	})
	r, err := c.PointerGet(context.Background(), "aa")
	if err != nil {
		t.Fatal(err)
	}
	if r.Counter != PointerFinalCounter || !r.Final || r.TransferredTo != "bb" || r.KindTag != 1 {
		t.Fatalf("record = %+v", r)
	}
}

func TestPointerMalformedCounterIsAnError(t *testing.T) {
	c, _ := pointerDaemon(t, map[string]func(map[string]any) (int, any){
		"GET /v1/pointers/aa": reply(200, map[string]any{"address": "aa", "counter": 3}),
	})
	if _, err := c.PointerGet(context.Background(), "aa"); err == nil {
		t.Fatal("a numeric counter must not read as a valid one")
	}
}

func TestPointerFinalityOpenAndForked(t *testing.T) {
	c, _ := pointerDaemon(t, map[string]func(map[string]any) (int, any){
		"GET /v1/pointers/aa/finality": reply(200, map[string]any{
			"address": "aa", "group": 7, "answered": 7, "status": "open", "counter": "3",
			"state": nil, "states": []any{}, "majority": nil, "transferred_to": nil,
		}),
		"GET /v1/pointers/bb/finality": reply(200, map[string]any{
			"address": "bb", "group": 7, "answered": 6, "status": "forked", "counter": nil,
			"states": []any{
				map[string]any{"state_id": "s1", "kind": "pointer", "kind_tag": 1, "target": "t1", "holders": 4, "transferred_to": "t1"},
				map[string]any{"state_id": "s2", "kind": "chunk", "kind_tag": 0, "target": "t2", "holders": 2, "transferred_to": nil},
			},
			"majority":       map[string]any{"state_id": "s1", "kind": "pointer", "kind_tag": 1, "target": "t1", "holders": 4, "transferred_to": "t1"},
			"transferred_to": nil,
		}),
	})

	open, err := c.PointerFinality(context.Background(), "aa")
	if err != nil {
		t.Fatal(err)
	}
	if open.Status != PointerOpen || open.Counter == nil || *open.Counter != 3 || open.State != nil {
		t.Fatalf("open = %+v", open)
	}

	forked, err := c.PointerFinality(context.Background(), "bb")
	if err != nil {
		t.Fatal(err)
	}
	if forked.Status != PointerForked || forked.Counter != nil || len(forked.States) != 2 ||
		forked.Majority == nil || forked.Majority.Holders != 4 || forked.States[1].TransferredTo != "" {
		t.Fatalf("forked = %+v", forked)
	}
}

func TestPointerControllerAndResolve(t *testing.T) {
	c, _ := pointerDaemon(t, map[string]func(map[string]any) (int, any){
		"GET /v1/pointers/aa/controller": reply(200, map[string]any{"pointer": "cc", "transfers": []any{"bb", "cc"}, "frozen": false}),
		"GET /v1/pointers/aa/resolve":    reply(200, map[string]any{"kind": "unknown", "kind_tag": 42, "target": "tt"}),
	})
	ctl, err := c.PointerController(context.Background(), "aa")
	if err != nil {
		t.Fatal(err)
	}
	if ctl.Pointer != "cc" || len(ctl.Transfers) != 2 || ctl.Frozen {
		t.Fatalf("controller = %+v", ctl)
	}
	res, err := c.PointerResolve(context.Background(), "aa")
	if err != nil {
		t.Fatal(err)
	}
	if res.Kind != "unknown" || res.KindTag != 42 || res.Target != "tt" {
		t.Fatalf("resolve = %+v", res)
	}
}

func TestPointerTransferKeepsAFailedFinalityCheck(t *testing.T) {
	c, last := pointerDaemon(t, map[string]func(map[string]any) (int, any){
		"POST /v1/pointers/transfer": reply(200, map[string]any{
			"address": "aa", "state_id": "ss", "finality": nil, "finality_error": "only 3 answered",
		}),
	})
	tr, err := c.PointerTransfer(context.Background(), "aa", "bb")
	if err != nil {
		t.Fatal(err)
	}
	if tr.Finality != nil || tr.FinalityError != "only 3 answered" {
		t.Fatalf("transfer = %+v", tr)
	}
	if (*last)["recipient"] != "bb" {
		t.Fatalf("body = %v", *last)
	}
}

func TestPointerPrepareAndFinalize(t *testing.T) {
	c, last := pointerDaemon(t, map[string]func(map[string]any) (int, any){
		"POST /v1/pointers/prepare": reply(200, map[string]any{
			"upload_id": "up", "op": "transfer", "address": "aa", "state_id": "ss",
			"counter": "18446744073709551615", "payment_type": "wave_batch",
			"payments":     []any{map[string]any{"quote_hash": "0xq", "rewards_address": "0xr", "amount": "5"}},
			"total_amount": "5", "payment_vault_address": "0xv", "payment_token_address": "0xt", "rpc_url": "http://rpc",
		}),
		"POST /v1/pointers/finalize": reply(200, map[string]any{
			"address": "aa", "state_id": "ss", "counter": "18446744073709551615",
			"finality": map[string]any{"address": "aa", "group": 7, "answered": 7, "status": "final",
				"state":  map[string]any{"state_id": "ss", "kind": "pointer", "kind_tag": 1, "target": "bb", "holders": 7, "transferred_to": "bb"},
				"states": []any{}, "transferred_to": "bb"},
		}),
	})

	prep, err := c.PointerPrepare(context.Background(), PointerPrepareRequest{Owner: "aa", Op: PointerOpTransfer, Recipient: "bb"})
	if err != nil {
		t.Fatal(err)
	}
	if (*last)["op"] != "transfer" || (*last)["recipient"] != "bb" {
		t.Fatalf("body = %v", *last)
	}
	if _, sent := (*last)["target"]; sent {
		t.Fatalf("a transfer sends no target: %v", *last)
	}
	if prep.UploadID != "up" || prep.Counter != PointerFinalCounter || len(prep.Payments) != 1 || prep.Payments[0].Amount != "5" {
		t.Fatalf("prepare = %+v", prep)
	}

	fin, err := c.PointerFinalize(context.Background(), "up", map[string]string{"0xq": "0xtx"})
	if err != nil {
		t.Fatal(err)
	}
	if fin.Finality == nil || fin.Finality.Status != PointerFinal || fin.Finality.TransferredTo != "bb" {
		t.Fatalf("finalize = %+v", fin)
	}
}

func TestPointerErrorsMapByCode(t *testing.T) {
	cases := []struct {
		status int
		body   map[string]any
		check  func(error) bool
	}{
		{409, map[string]any{"error": "x", "code": "POINTER_FINAL"}, func(e error) bool { var t *PointerFinalError; return errors.As(e, &t) }},
		{409, map[string]any{"error": "x", "code": "POINTER_FORKED"}, func(e error) bool { var t *ForkError; return errors.As(e, &t) }},
		{409, map[string]any{"error": "x", "code": "CONFLICT"}, func(e error) bool { var t *ConflictError; return errors.As(e, &t) }},
		{409, map[string]any{"error": "x", "code": "ALREADY_EXISTS"}, func(e error) bool { var t *AlreadyExistsError; return errors.As(e, &t) }},
		{503, map[string]any{"error": "x", "code": "SERVICE_UNAVAILABLE"}, func(e error) bool { var t *ServiceUnavailableError; return errors.As(e, &t) }},
		{503, map[string]any{"error": "x", "code": "CLOSE_GROUP_SHORTFALL", "retryable": true}, func(e error) bool {
			var t *CloseGroupShortfallError
			return errors.As(e, &t) && t.Retryable && t.StatusCode == 503
		}},
		{503, map[string]any{"error": "x", "code": "CLOSE_GROUP_SHORTFALL"}, func(e error) bool {
			var t *CloseGroupShortfallError
			return errors.As(e, &t) && !t.Retryable
		}},
	}
	for _, tc := range cases {
		c, _ := pointerDaemon(t, map[string]func(map[string]any) (int, any){
			"POST /v1/pointers/update": reply(tc.status, tc.body),
		})
		_, err := c.PointerUpdate(context.Background(), "aa", "tt", "")
		if err == nil || !tc.check(err) {
			t.Errorf("%d %v: got %T %v", tc.status, tc.body["code"], err, err)
		}
	}
}
