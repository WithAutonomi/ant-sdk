package antd

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"

	pb "github.com/WithAutonomi/ant-sdk/antd-go/proto/antd/v1"
)

// Pointers over gRPC: the same methods, types and errors as the REST Client
// (see pointers.go). Each call captures the trailers, because the daemon
// sends the error code there (x-antd-error-code) for the errors that share a
// gRPC status with older ones: POINTER_FINAL and POINTER_FORKED
// (FAILED_PRECONDITION, otherwise a PaymentError), CONFLICT (ABORTED) and
// CLOSE_GROUP_SHORTFALL (UNAVAILABLE, otherwise a NetworkError).

// pointerErrorCodeKey is the metadata key the daemon puts its error code in.
const pointerErrorCodeKey = "x-antd-error-code"

// closeGroupRetainedHint closes a CLOSE_GROUP_SHORTFALL message when a
// pointer finalize kept the paid state for a repeat with the same upload_id.
const closeGroupRetainedHint = "(paid attempt retained"

// errorFromGrpcTrailer maps a failed pointer RPC, preferring the daemon's
// x-antd-error-code over the bare status code where one was sent.
func errorFromGrpcTrailer(err error, trailer metadata.MD) error {
	if err == nil {
		return nil
	}
	if codes := trailer.Get(pointerErrorCodeKey); len(codes) > 0 {
		msg := err.Error()
		if st, ok := status.FromError(err); ok {
			msg = st.Message()
		}
		statusCode := 409
		var body map[string]any
		if codes[0] == "CLOSE_GROUP_SHORTFALL" {
			statusCode = 503
			body = map[string]any{"retryable": strings.Contains(msg, closeGroupRetainedHint)}
		}
		if mapped := errorForCode(codes[0], statusCode, msg, body); mapped != nil {
			return mapped
		}
	}
	return errorFromGrpc(err)
}

// pointerCall runs one PointerService RPC under the client's timeout and maps
// its error with the trailers it sent.
func pointerCall[Resp any](c *GrpcClient, parent context.Context, call func(context.Context, ...grpc.CallOption) (Resp, error)) (Resp, error) {
	ctx, cancel := c.ctx(parent)
	defer cancel()
	var trailer metadata.MD
	resp, err := call(ctx, grpc.Trailer(&trailer))
	if err != nil {
		var zero Resp
		return zero, errorFromGrpcTrailer(err, trailer)
	}
	return resp, nil
}

// parseCounter parses a decimal counter from the proto's string field.
func parseCounter(field, s string) (uint64, error) {
	n, err := strconv.ParseUint(s, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("antd: pointer %s %q is not a decimal counter", field, s)
	}
	return n, nil
}

// PointerKeys returns the addresses of the pointers this daemon holds owner
// keys for. Mirrors Client.PointerKeys.
func (c *GrpcClient) PointerKeys(ctx context.Context) ([]string, error) {
	resp, err := pointerCall(c, ctx, func(ctx context.Context, opts ...grpc.CallOption) (*pb.ListPointerKeysResponse, error) {
		return c.pointer.ListKeys(ctx, &pb.ListPointerKeysRequest{}, opts...)
	})
	if err != nil {
		return nil, err
	}
	addresses := make([]string, 0, len(resp.GetKeys()))
	for _, k := range resp.GetKeys() {
		addresses = append(addresses, k.GetAddress())
	}
	return addresses, nil
}

// PointerCreate mirrors Client.PointerCreate.
func (c *GrpcClient) PointerCreate(ctx context.Context, owner, target string, kind PointerTargetKind) (*PointerWrite, error) {
	return c.pointerWrite(ctx, owner, target, kind, c.pointer.Create)
}

// PointerUpdate mirrors Client.PointerUpdate.
func (c *GrpcClient) PointerUpdate(ctx context.Context, owner, target string, kind PointerTargetKind) (*PointerWrite, error) {
	return c.pointerWrite(ctx, owner, target, kind, c.pointer.Update)
}

func (c *GrpcClient) pointerWrite(
	ctx context.Context,
	owner, target string,
	kind PointerTargetKind,
	rpc func(context.Context, *pb.PointerWriteRequest, ...grpc.CallOption) (*pb.PointerWriteResponse, error),
) (*PointerWrite, error) {
	req := &pb.PointerWriteRequest{Owner: owner, Target: target, Kind: string(kind)}
	resp, err := pointerCall(c, ctx, func(ctx context.Context, opts ...grpc.CallOption) (*pb.PointerWriteResponse, error) {
		return rpc(ctx, req, opts...)
	})
	if err != nil {
		return nil, err
	}
	counter, err := parseCounter("counter", resp.GetCounter())
	if err != nil {
		return nil, err
	}
	return &PointerWrite{Address: resp.GetAddress(), StateID: resp.GetStateId(), Counter: counter}, nil
}

// PointerTransfer mirrors Client.PointerTransfer.
func (c *GrpcClient) PointerTransfer(ctx context.Context, owner, recipient string) (*PointerTransferResult, error) {
	resp, err := pointerCall(c, ctx, func(ctx context.Context, opts ...grpc.CallOption) (*pb.PointerTransferResponse, error) {
		return c.pointer.Transfer(ctx, &pb.PointerTransferRequest{Owner: owner, Recipient: recipient}, opts...)
	})
	if err != nil {
		return nil, err
	}
	r := &PointerTransferResult{
		Address:       resp.GetAddress(),
		StateID:       resp.GetStateId(),
		FinalityError: resp.GetFinalityError(),
	}
	if f := resp.GetFinality(); f != nil {
		if r.Finality, err = pbPointerFinality(f); err != nil {
			return nil, err
		}
	}
	return r, nil
}

// PointerGet mirrors Client.PointerGet.
func (c *GrpcClient) PointerGet(ctx context.Context, address string) (*PointerRecord, error) {
	resp, err := pointerCall(c, ctx, func(ctx context.Context, opts ...grpc.CallOption) (*pb.PointerRecord, error) {
		return c.pointer.Get(ctx, &pb.GetPointerRequest{Address: address}, opts...)
	})
	if err != nil {
		return nil, err
	}
	counter, err := parseCounter("counter", resp.GetCounter())
	if err != nil {
		return nil, err
	}
	return &PointerRecord{
		Address:       resp.GetAddress(),
		Owner:         resp.GetOwner(),
		Counter:       counter,
		Kind:          resp.GetKind(),
		KindTag:       uint8(resp.GetKindTag()),
		Target:        resp.GetTarget(),
		StateID:       resp.GetStateId(),
		Final:         resp.GetIsFinal(),
		TransferredTo: resp.GetTransferredTo(),
	}, nil
}

// PointerResolve mirrors Client.PointerResolve.
func (c *GrpcClient) PointerResolve(ctx context.Context, address string) (*PointerTarget, error) {
	resp, err := pointerCall(c, ctx, func(ctx context.Context, opts ...grpc.CallOption) (*pb.PointerResolved, error) {
		return c.pointer.Resolve(ctx, &pb.ResolvePointerRequest{Address: address}, opts...)
	})
	if err != nil {
		return nil, err
	}
	return &PointerTarget{Kind: resp.GetKind(), KindTag: uint8(resp.GetKindTag()), Target: resp.GetTarget()}, nil
}

// PointerFinality mirrors Client.PointerFinality.
func (c *GrpcClient) PointerFinality(ctx context.Context, address string) (*PointerFinality, error) {
	resp, err := pointerCall(c, ctx, func(ctx context.Context, opts ...grpc.CallOption) (*pb.PointerFinality, error) {
		return c.pointer.Finality(ctx, &pb.PointerFinalityRequest{Address: address}, opts...)
	})
	if err != nil {
		return nil, err
	}
	return pbPointerFinality(resp)
}

// PointerController mirrors Client.PointerController.
func (c *GrpcClient) PointerController(ctx context.Context, address string) (*PointerController, error) {
	resp, err := pointerCall(c, ctx, func(ctx context.Context, opts ...grpc.CallOption) (*pb.PointerController, error) {
		return c.pointer.Controller(ctx, &pb.PointerControllerRequest{Address: address}, opts...)
	})
	if err != nil {
		return nil, err
	}
	transfers := append([]string{}, resp.GetTransfers()...)
	return &PointerController{Pointer: resp.GetPointer(), Transfers: transfers, Frozen: resp.GetFrozen()}, nil
}

// PointerPrepare mirrors Client.PointerPrepare.
func (c *GrpcClient) PointerPrepare(ctx context.Context, req PointerPrepareRequest) (*PointerPrepareResult, error) {
	resp, err := pointerCall(c, ctx, func(ctx context.Context, opts ...grpc.CallOption) (*pb.PreparePointerResponse, error) {
		return c.pointer.Prepare(ctx, &pb.PreparePointerRequest{
			Owner:               req.Owner,
			Op:                  string(req.Op),
			Target:              req.Target,
			Kind:                string(req.Kind),
			Recipient:           req.Recipient,
			IncludeSignedQuotes: req.IncludeSignedQuotes,
		}, opts...)
	})
	if err != nil {
		return nil, err
	}
	counter, err := parseCounter("counter", resp.GetCounter())
	if err != nil {
		return nil, err
	}
	r := &PointerPrepareResult{
		UploadID:            resp.GetUploadId(),
		Op:                  PointerOp(resp.GetOp()),
		Address:             resp.GetAddress(),
		StateID:             resp.GetStateId(),
		Counter:             counter,
		PaymentType:         resp.GetPaymentType(),
		TotalAmount:         resp.GetTotalAmount(),
		PaymentVaultAddress: resp.GetPaymentVaultAddress(),
		PaymentTokenAddress: resp.GetPaymentTokenAddress(),
		RPCUrl:              resp.GetRpcUrl(),
		SignedQuotes:        pbSignedQuotes(resp.GetSignedQuotes()),
	}
	for _, p := range resp.GetPayments() {
		r.Payments = append(r.Payments, PaymentInfo{
			QuoteHash:      p.GetQuoteHash(),
			RewardsAddress: p.GetRewardsAddress(),
			Amount:         p.GetAmount(),
		})
	}
	return r, nil
}

// PointerFinalize mirrors Client.PointerFinalize. A CloseGroupShortfallError
// with Retryable set means the daemon kept the paid state: repeat the call
// with the same uploadID.
func (c *GrpcClient) PointerFinalize(ctx context.Context, uploadID string, txHashes map[string]string) (*PointerFinalizeResult, error) {
	resp, err := pointerCall(c, ctx, func(ctx context.Context, opts ...grpc.CallOption) (*pb.FinalizePointerResponse, error) {
		return c.pointer.Finalize(ctx, &pb.FinalizePointerRequest{UploadId: uploadID, TxHashes: txHashes}, opts...)
	})
	if err != nil {
		return nil, err
	}
	counter, err := parseCounter("counter", resp.GetCounter())
	if err != nil {
		return nil, err
	}
	r := &PointerFinalizeResult{Address: resp.GetAddress(), StateID: resp.GetStateId(), Counter: counter}
	if f := resp.GetFinality(); f != nil {
		if r.Finality, err = pbPointerFinality(f); err != nil {
			return nil, err
		}
	}
	return r, nil
}

func pbPointerFinalState(s *pb.PointerFinalState) PointerFinalState {
	return PointerFinalState{
		StateID:       s.GetStateId(),
		Kind:          s.GetKind(),
		KindTag:       uint8(s.GetKindTag()),
		Target:        s.GetTarget(),
		Holders:       s.GetHolders(),
		TransferredTo: s.GetTransferredTo(),
	}
}

// pbPointerFinality converts the proto shape, where an unset counter is the
// empty string and an unset state an absent message.
func pbPointerFinality(f *pb.PointerFinality) (*PointerFinality, error) {
	r := &PointerFinality{
		Address:       f.GetAddress(),
		Group:         f.GetGroup(),
		Answered:      f.GetAnswered(),
		Status:        PointerFinalityStatus(f.GetStatus()),
		TransferredTo: f.GetTransferredTo(),
	}
	if s := f.GetCounter(); s != "" {
		counter, err := parseCounter("counter", s)
		if err != nil {
			return nil, err
		}
		r.Counter = &counter
	}
	if s := f.GetState(); s != nil {
		state := pbPointerFinalState(s)
		r.State = &state
	}
	for _, s := range f.GetStates() {
		r.States = append(r.States, pbPointerFinalState(s))
	}
	if m := f.GetMajority(); m != nil {
		majority := pbPointerFinalState(m)
		r.Majority = &majority
	}
	return r, nil
}
