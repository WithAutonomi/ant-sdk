# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/antd/version"
require_relative "../lib/antd/models"
require_relative "../lib/antd/errors"

# The pointer methods need the real GrpcClient and the generated
# PointerService stubs, so these tests skip without the grpc gem.
begin
  require_relative "../lib/antd/grpc_client"
rescue LoadError
  # grpc gem not installed
end

# Pointer API over gRPC against a fake PointerService stub that records each
# request and answers with real proto messages, so unset fields read exactly
# as they do off the wire ("" strings, nil sub-messages).
class TestGrpcPointers < Minitest::Test
  A = "a" * 64
  B = "b" * 64
  T1 = "1" * 64
  STATE = "5" * 64
  MAX = "18446744073709551615"
  V1 = Antd::V1 if defined?(Antd::V1)

  # Records every call as [rpc, request]; answers with the response
  # registered for the rpc, raising it if it is an exception.
  class PointerStub
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    %i[list_keys create update transfer get resolve finality controller prepare finalize].each do |rpc|
      define_method(rpc) do |req|
        @calls << [rpc, req]
        resp = @responses.fetch(rpc)
        raise resp if resp.is_a?(Exception)

        resp
      end
    end
  end

  def setup
    skip "needs the grpc gem and the generated PointerService stubs" unless defined?(Antd::V1::PointerService)
  end

  def test_pointer_keys
    client, = client_with(list_keys: V1::ListPointerKeysResponse.new(keys: [V1::PointerKey.new(address: A),
                                                                             V1::PointerKey.new(address: B)]))
    assert_equal [A, B], client.pointer_keys
  end

  def test_pointer_create_sends_an_empty_kind_by_default
    client, stub = client_with(create: write_response("0"))
    w = client.pointer_create(A, T1)
    assert_instance_of Antd::PointerWriteResult, w
    assert_equal [A, STATE, 0], [w.address, w.state_id, w.counter]
    rpc, req = stub.calls.first
    assert_equal :create, rpc
    assert_equal [A, T1, ""], [req.owner, req.target, req.kind]
  end

  def test_pointer_update_sends_kind
    client, stub = client_with(update: write_response("9"))
    assert_equal 9, client.pointer_update(A, B, kind: Antd::PointerKind::POINTER).counter
    rpc, req = stub.calls.first
    assert_equal :update, rpc
    assert_equal "pointer", req.kind
  end

  def test_pointer_transfer_with_finality
    finality = V1::PointerFinality.new(address: A, group: 7, answered: 7, status: "final", transferred_to: B,
                                       state: final_state(B, transferred_to: B))
    client, stub = client_with(transfer: V1::PointerTransferResponse.new(address: A, state_id: STATE, finality: finality))
    t = client.pointer_transfer(A, B)
    assert_equal [A, STATE, nil], [t.address, t.state_id, t.finality_error]
    assert t.finality.final?
    assert_equal B, t.finality.transferred_to
    assert_equal B, t.finality.state.transferred_to
    _, req = stub.calls.first
    assert_equal [A, B], [req.owner, req.recipient]
  end

  def test_pointer_transfer_without_finality
    client, = client_with(transfer: V1::PointerTransferResponse.new(address: A, state_id: STATE,
                                                                    finality_error: "only 3 of 7 answered"))
    t = client.pointer_transfer(A, B)
    assert_nil t.finality
    assert_equal "only 3 of 7 answered", t.finality_error
  end

  def test_pointer_get_final_record
    record = V1::PointerRecord.new(address: A, owner: "c" * 3904, counter: MAX, kind: "pointer", kind_tag: 1,
                                   target: B, state_id: STATE, is_final: true, transferred_to: B)
    client, stub = client_with(get: record)
    r = client.pointer_get(A)
    assert_instance_of Antd::PointerRecord, r
    assert_equal Antd::POINTER_FINAL_COUNTER, r.counter
    assert r.final?
    assert_equal [B, Antd::PointerKind::POINTER], [r.transferred_to, r.target_kind]
    assert_equal A, stub.calls.first[1].address
  end

  # proto3 sends an unset transferred_to as "": it reads as nil, as REST's null.
  def test_pointer_get_open_record_reads_empty_transferred_to_as_nil
    client, = client_with(get: V1::PointerRecord.new(address: A, counter: "2", kind: "chunk", target: T1))
    r = client.pointer_get(A)
    assert_equal 2, r.counter
    refute r.final?
    assert_nil r.transferred_to
    assert_equal 0, r.kind_tag
  end

  def test_pointer_resolve
    client, = client_with(resolve: V1::PointerResolved.new(kind: "chunk", kind_tag: 0, target: T1))
    res = client.pointer_resolve(A)
    assert_instance_of Antd::PointerTarget, res
    assert_equal ["chunk", 0, T1], [res.kind, res.kind_tag, res.target]
  end

  def test_pointer_finality_open_reads_unset_fields_as_nil
    client, = client_with(finality: V1::PointerFinality.new(address: A, group: 7, answered: 6, status: "open",
                                                            counter: "1"))
    f = client.pointer_finality(A)
    assert_equal [A, 7, 6, "open", 1], [f.address, f.group, f.answered, f.status, f.counter]
    assert_nil f.state
    assert_nil f.majority
    assert_nil f.transferred_to
    assert_equal [], f.states
  end

  def test_pointer_finality_open_with_empty_counter
    client, = client_with(finality: V1::PointerFinality.new(address: A, status: "open"))
    assert_nil client.pointer_finality(A).counter
  end

  def test_pointer_finality_forked
    states = [final_state(T1, holders: 4), final_state(B, holders: 2)]
    client, = client_with(finality: V1::PointerFinality.new(address: A, status: "forked", states: states,
                                                            majority: final_state(T1, holders: 4)))
    f = client.pointer_finality(A)
    assert_equal [T1, B], f.states.map(&:target)
    assert_equal [4, 2], f.states.map(&:holders)
    assert_equal T1, f.majority.target
    assert_nil f.states.first.transferred_to
  end

  def test_pointer_finality_unknown_status_is_kept
    client, = client_with(finality: V1::PointerFinality.new(address: A, status: "contested"))
    f = client.pointer_finality(A)
    assert_equal "contested", f.status
    refute f.status_known?
  end

  def test_pointer_controller
    client, = client_with(controller: V1::PointerController.new(pointer: B, transfers: [B], frozen: false))
    c = client.pointer_controller(A)
    assert_equal [B, [B], false], [c.pointer, c.transfers, c.frozen]
  end

  def test_pointer_prepare
    resp = V1::PreparePointerResponse.new(
      upload_id: "up-1", op: "update", address: A, state_id: STATE, counter: "1", payment_type: "wave_batch",
      payments: [V1::PaymentEntry.new(quote_hash: "0xq1", rewards_address: "0xr1", amount: "10")],
      total_amount: "10", payment_vault_address: "0xvault", payment_token_address: "0xtoken",
      rpc_url: "http://localhost:8545",
      signed_quotes: [V1::SignedQuoteEntry.new(quote_hash: "0xq1", quote: "quote".b),
                      V1::SignedQuoteEntry.new(quote_hash: "0xq2", quote: "q".b, commitment_sidecar: "sc".b)]
    )
    client, stub = client_with(prepare: resp)
    p = client.pointer_prepare(A, Antd::PointerOp::UPDATE, target: T1, include_signed_quotes: true)
    assert_equal ["up-1", "update", A, STATE, 1, "wave_batch"],
                 [p.upload_id, p.op, p.address, p.state_id, p.counter, p.payment_type]
    assert_equal ["0xq1", "0xr1", "10"], [p.payments[0].quote_hash, p.payments[0].rewards_address, p.payments[0].amount]
    assert_equal ["10", "0xvault", "0xtoken", "http://localhost:8545"],
                 [p.total_amount, p.payment_vault_address, p.payment_token_address, p.rpc_url]
    # Bytes on the wire, base64 in the result: the form REST returns.
    assert_equal ["cXVvdGU=", nil], [p.signed_quotes[0].quote, p.signed_quotes[0].commitment_sidecar]
    assert_equal ["cQ==", "c2M="], [p.signed_quotes[1].quote, p.signed_quotes[1].commitment_sidecar]

    _, req = stub.calls.first
    assert_equal [A, "update", T1, "", ""], [req.owner, req.op, req.target, req.kind, req.recipient]
    assert req.include_signed_quotes
  end

  def test_pointer_finalize_forwards_tx_hashes
    client, stub = client_with(finalize: V1::FinalizePointerResponse.new(address: A, state_id: STATE, counter: "1"))
    r = client.pointer_finalize("up-1", { "0xq1" => "0xtx" })
    assert_equal [A, STATE, 1, nil], [r.address, r.state_id, r.counter, r.finality]
    _, req = stub.calls.first
    assert_equal "up-1", req.upload_id
    assert_equal({ "0xq1" => "0xtx" }, req.tx_hashes.to_h)
  end

  def test_malformed_counter_is_an_error_not_zero
    ["", "-1", "1_0", MAX.succ].each do |bad|
      client, = client_with(create: write_response(bad))
      assert_raises(Antd::InternalError, bad.inspect) { client.pointer_create(A, T1) }
    end
  end

  # --- errors: the x-antd-error-code trailer ---

  def test_tagged_failed_precondition_is_pointer_final
    err = assert_raises(Antd::PointerFinalError) do
      failing(GRPC::FailedPrecondition.new("Pointer is final: x", tag("POINTER_FINAL"))).pointer_update(A, T1)
    end
    refute_kind_of Antd::PaymentError, err
    assert_equal 409, err.status_code
    assert_includes err.message, "Pointer is final"
  end

  def test_tagged_failed_precondition_is_pointer_forked
    err = assert_raises(Antd::PointerForkedError) do
      failing(GRPC::FailedPrecondition.new("Pointer is forked: x", tag("POINTER_FORKED"))).pointer_get(A)
    end
    assert_kind_of Antd::ForkError, err
  end

  def test_tagged_aborted_is_conflict
    err = assert_raises(Antd::ConflictError) do
      failing(GRPC::Aborted.new("Conflict: pending", tag("CONFLICT"))).pointer_prepare(A, "update", target: T1)
    end
    assert_equal 409, err.status_code
  end

  def test_tagged_unavailable_is_close_group_shortfall
    details = "Close group shortfall: stored on 4 of 5 (paid attempt retained: call finalize again with the " \
              "same upload_id to store it against the same payment)"
    err = assert_raises(Antd::CloseGroupShortfallError) do
      failing(GRPC::Unavailable.new(details, tag("CLOSE_GROUP_SHORTFALL"))).pointer_finalize("up-1", {})
    end
    assert err.retryable
    assert_equal 503, err.status_code

    err = assert_raises(Antd::CloseGroupShortfallError) do
      failing(GRPC::Unavailable.new("Close group shortfall: only 3 answered", tag("CLOSE_GROUP_SHORTFALL")))
        .pointer_get(A)
    end
    refute err.retryable
  end

  # Untagged statuses keep the code-based mapping: FAILED_PRECONDITION is
  # still a payment error, UNAVAILABLE a network error.
  def test_untagged_statuses_keep_their_mapping
    assert_raises(Antd::PaymentError) { failing(GRPC::FailedPrecondition.new("insufficient funds")).pointer_create(A, T1) }
    assert_raises(Antd::NetworkError) { failing(GRPC::Unavailable.new("down")).pointer_get(A) }
    assert_raises(Antd::AlreadyExistsError) { failing(GRPC::AlreadyExists.new("exists")).pointer_create(A, T1) }
    assert_raises(Antd::NotFoundError) { failing(GRPC::NotFound.new("none")).pointer_get(A) }
    assert_raises(Antd::BadRequestError) { failing(GRPC::InvalidArgument.new("no key")).pointer_create(A, T1) }
  end

  # A tag is trusted only on the status code the daemon pairs it with.
  def test_a_tag_on_another_status_code_is_ignored
    err = assert_raises(Antd::AntdError) { failing(GRPC::Aborted.new("x", tag("POINTER_FINAL"))).pointer_get(A) }
    refute_kind_of Antd::PointerFinalError, err
    assert_raises(Antd::PaymentError) { failing(GRPC::FailedPrecondition.new("x", tag("CONFLICT"))).pointer_get(A) }
    assert_raises(Antd::PaymentError) { failing(GRPC::FailedPrecondition.new("x", tag("SOMETHING_NEW"))).pointer_get(A) }
  end

  # The trailer is read on every call, not only the pointer methods.
  def test_tag_applies_to_other_services
    chunk_stub = Object.new
    def chunk_stub.put(_req)
      raise GRPC::Unavailable.new("Close group shortfall", { "x-antd-error-code" => "CLOSE_GROUP_SHORTFALL" })
    end
    client = Antd::GrpcClient.allocate
    client.instance_variable_set(:@chunk_stub, chunk_stub)
    assert_raises(Antd::CloseGroupShortfallError) { client.chunk_put("x") }
  end

  private

  def client_with(responses)
    stub = PointerStub.new(responses)
    client = Antd::GrpcClient.allocate
    client.instance_variable_set(:@pointer_stub, stub)
    [client, stub]
  end

  def failing(error)
    rpcs = %i[list_keys create update transfer get resolve finality controller prepare finalize]
    client_with(rpcs.to_h { |rpc| [rpc, error] }).first
  end

  def tag(code)
    { "x-antd-error-code" => code }
  end

  def write_response(counter)
    V1::PointerWriteResponse.new(address: A, state_id: STATE, counter: counter)
  end

  def final_state(target, holders: 7, transferred_to: "")
    V1::PointerFinalState.new(state_id: STATE, kind: "chunk", kind_tag: 0, target: target, holders: holders,
                              transferred_to: transferred_to)
  end
end
