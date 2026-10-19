# frozen_string_literal: true

require_relative "test_helper"
require "json"

# Pointer API over REST against a mocked daemon: request shapes, response
# parsing (counters up to u64::MAX, nulls as nil), and the error codes that
# share an HTTP status with older errors.
class TestPointers < Minitest::Test
  BASE = "http://localhost:8082"
  A = "a" * 64
  B = "b" * 64
  T1 = "1" * 64
  T2 = "2" * 64
  STATE = "5" * 64
  MAX = "18446744073709551615"
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  def setup
    @client = Antd::Client.new(base_url: BASE)
  end

  # --- keys ---

  def test_pointer_keys
    stub_json(:get, "/v1/pointers/keys", { keys: [{ address: A }, { address: B }] })
    assert_equal [A, B], @client.pointer_keys
  end

  def test_pointer_keys_empty
    stub_json(:get, "/v1/pointers/keys", { keys: [] })
    assert_equal [], @client.pointer_keys
  end

  # --- writes ---

  def test_pointer_create_omits_kind_by_default
    stub_request(:post, "#{BASE}/v1/pointers")
      .with(body: { owner: A, target: T1 }.to_json)
      .to_return(status: 200, body: { address: A, state_id: STATE, counter: "0" }.to_json, headers: JSON_HEADERS)

    w = @client.pointer_create(A, T1)
    assert_instance_of Antd::PointerWriteResult, w
    assert_equal [A, STATE, 0], [w.address, w.state_id, w.counter]
  end

  def test_pointer_create_sends_kind
    stub_request(:post, "#{BASE}/v1/pointers")
      .with(body: { owner: A, target: B, kind: "pointer" }.to_json)
      .to_return(status: 200, body: { address: A, state_id: STATE, counter: "0" }.to_json, headers: JSON_HEADERS)

    assert_equal 0, @client.pointer_create(A, B, kind: Antd::PointerKind::POINTER).counter
  end

  def test_pointer_update
    stub_request(:post, "#{BASE}/v1/pointers/update")
      .with(body: { owner: A, target: T2, kind: "chunk" }.to_json)
      .to_return(status: 200, body: { address: A, state_id: STATE, counter: "7" }.to_json, headers: JSON_HEADERS)

    assert_equal 7, @client.pointer_update(A, T2, kind: Antd::PointerKind::CHUNK).counter
  end

  def test_pointer_transfer_with_finality
    body = {
      address: A, state_id: STATE,
      finality: finality_json(status: "final", counter: nil, transferred_to: B,
                              state: final_state_json(target: B, kind: "pointer", kind_tag: 1, transferred_to: B))
    }
    stub_request(:post, "#{BASE}/v1/pointers/transfer")
      .with(body: { owner: A, recipient: B }.to_json)
      .to_return(status: 200, body: body.to_json, headers: JSON_HEADERS)

    t = @client.pointer_transfer(A, B)
    assert_instance_of Antd::PointerTransferResult, t
    assert_equal [A, STATE, nil], [t.address, t.state_id, t.finality_error]
    f = t.finality
    assert f.final?
    assert_equal B, f.transferred_to
    assert_nil f.counter
    assert_equal B, f.state.transferred_to
    assert_equal 1, f.state.kind_tag
  end

  # The finality check after a transfer failed: the transfer is stored
  # anyway, finality is null and finality_error says why.
  def test_pointer_transfer_without_finality
    stub_json(:post, "/v1/pointers/transfer",
              { address: A, state_id: STATE, finality: nil, finality_error: "only 3 of 7 answered" })

    t = @client.pointer_transfer(A, B)
    assert_nil t.finality
    assert_equal "only 3 of 7 answered", t.finality_error
  end

  # --- reads ---

  def test_pointer_get_final_record
    stub_json(:get, "/v1/pointers/#{A}", record_json(counter: MAX, is_final: true, transferred_to: B,
                                                     kind: "pointer", kind_tag: 1, target: B))

    r = @client.pointer_get(A)
    assert_instance_of Antd::PointerRecord, r
    assert_equal Antd::POINTER_FINAL_COUNTER, r.counter
    assert_equal 2**64 - 1, r.counter
    assert r.final?
    assert r.is_final
    assert_equal B, r.transferred_to
    assert_equal Antd::PointerKind::POINTER, r.target_kind
    assert_equal "c" * 3904, r.owner
  end

  def test_pointer_get_open_record_reads_null_transferred_to_as_nil
    stub_json(:get, "/v1/pointers/#{A}", record_json(counter: "3", is_final: false, transferred_to: nil))

    r = @client.pointer_get(A)
    assert_equal 3, r.counter
    refute r.final?
    assert_nil r.transferred_to
    assert_equal "chunk", r.kind
    assert_equal 0, r.kind_tag
    assert_equal Antd::PointerKind::CHUNK, r.target_kind
  end

  def test_pointer_get_unknown_kind_keeps_tag
    stub_json(:get, "/v1/pointers/#{A}", record_json(counter: "0", kind: "unknown", kind_tag: 42))

    r = @client.pointer_get(A)
    assert_equal ["unknown", 42], [r.kind, r.kind_tag]
    assert_nil r.target_kind
  end

  def test_pointer_get_not_found
    stub_request(:get, "#{BASE}/v1/pointers/#{A}")
      .to_return(status: 404, body: { error: "Record not found: pointer", code: "NOT_FOUND" }.to_json)
    assert_raises(Antd::NotFoundError) { @client.pointer_get(A) }
  end

  def test_pointer_resolve
    stub_json(:get, "/v1/pointers/#{A}/resolve", { kind: "chunk", kind_tag: 0, target: T2 })

    res = @client.pointer_resolve(A)
    assert_instance_of Antd::PointerTarget, res
    assert_equal ["chunk", 0, T2], [res.kind, res.kind_tag, res.target]
    assert_equal Antd::PointerKind::CHUNK, res.target_kind
  end

  def test_pointer_finality_open_reads_nulls_as_nil
    stub_json(:get, "/v1/pointers/#{A}/finality", finality_json(status: "open", counter: "1"))

    f = @client.pointer_finality(A)
    assert_instance_of Antd::PointerFinality, f
    assert_equal [A, 7, 7, "open", 1], [f.address, f.group, f.answered, f.status, f.counter]
    assert_nil f.state
    assert_nil f.majority
    assert_nil f.transferred_to
    assert_equal [], f.states
    refute f.final?
    assert f.status_known?
  end

  def test_pointer_finality_open_without_corroborated_counter
    stub_json(:get, "/v1/pointers/#{A}/finality", finality_json(status: "open", counter: nil))
    assert_nil @client.pointer_finality(A).counter
  end

  def test_pointer_finality_forked
    states = [final_state_json(target: T1, holders: 4), final_state_json(target: T2, holders: 2)]
    stub_json(:get, "/v1/pointers/#{A}/finality",
              finality_json(status: "forked", counter: nil, states: states, majority: states.first))

    f = @client.pointer_finality(A)
    assert_equal Antd::PointerFinalityStatus::FORKED, f.status
    assert_equal [T1, T2], f.states.map(&:target)
    assert_equal [4, 2], f.states.map(&:holders)
    assert_instance_of Antd::PointerFinalState, f.majority
    assert_equal T1, f.majority.target
    assert_nil f.state
  end

  # A status a newer daemon adds is kept verbatim, the "unknown" arm.
  def test_pointer_finality_unknown_status_is_kept
    stub_json(:get, "/v1/pointers/#{A}/finality", finality_json(status: "contested", counter: nil))

    f = @client.pointer_finality(A)
    assert_equal "contested", f.status
    refute f.status_known?
    refute f.final?
  end

  def test_pointer_finality_rejects_a_malformed_counter
    stub_json(:get, "/v1/pointers/#{A}/finality", finality_json(status: "open", counter: "-1"))
    assert_raises(Antd::InternalError) { @client.pointer_finality(A) }
  end

  def test_pointer_controller
    stub_json(:get, "/v1/pointers/#{A}/controller", { pointer: B, transfers: [B], frozen: false })

    c = @client.pointer_controller(A)
    assert_instance_of Antd::PointerController, c
    assert_equal [B, [B], false], [c.pointer, c.transfers, c.frozen]
  end

  # --- external signer ---

  def test_pointer_prepare_update
    stub_request(:post, "#{BASE}/v1/pointers/prepare")
      .with(body: { owner: A, op: "update", target: T2, kind: "chunk" }.to_json)
      .to_return(status: 200, body: prepare_json.to_json, headers: JSON_HEADERS)

    p = @client.pointer_prepare(A, Antd::PointerOp::UPDATE, target: T2, kind: Antd::PointerKind::CHUNK)
    assert_instance_of Antd::PointerPrepareResult, p
    assert_equal ["up-1", "update", A, STATE, 1, "wave_batch"],
                 [p.upload_id, p.op, p.address, p.state_id, p.counter, p.payment_type]
    assert_equal 1, p.payments.length
    assert_equal ["0xq1", "0xr1", "10"], [p.payments[0].quote_hash, p.payments[0].rewards_address, p.payments[0].amount]
    assert_equal ["10", "0xvault", "0xtoken", "http://localhost:8545"],
                 [p.total_amount, p.payment_vault_address, p.payment_token_address, p.rpc_url]
    assert_equal [], p.signed_quotes
  end

  def test_pointer_prepare_transfer_with_signed_quotes
    quotes = [{ quote_hash: "0xq1", quote: "cXVvdGU=" }, { quote_hash: "0xq2", quote: "cQ==", commitment_sidecar: "c2M=" }]
    stub_request(:post, "#{BASE}/v1/pointers/prepare")
      .with(body: { owner: A, op: "transfer", recipient: B, include_signed_quotes: true }.to_json)
      .to_return(status: 200, body: prepare_json(op: "transfer", counter: MAX, signed_quotes: quotes).to_json,
                 headers: JSON_HEADERS)

    p = @client.pointer_prepare(A, Antd::PointerOp::TRANSFER, recipient: B, include_signed_quotes: true)
    assert_equal Antd::POINTER_FINAL_COUNTER, p.counter
    assert_equal %w[0xq1 0xq2], p.signed_quotes.map(&:quote_hash)
    assert_equal "cXVvdGU=", p.signed_quotes[0].quote
    assert_nil p.signed_quotes[0].commitment_sidecar
    assert_equal "c2M=", p.signed_quotes[1].commitment_sidecar
  end

  def test_pointer_finalize
    stub_request(:post, "#{BASE}/v1/pointers/finalize")
      .with(body: { upload_id: "up-1", tx_hashes: { "0xq1" => "0xtx" } }.to_json)
      .to_return(status: 200, body: { address: A, state_id: STATE, counter: "1" }.to_json, headers: JSON_HEADERS)

    r = @client.pointer_finalize("up-1", { "0xq1" => "0xtx" })
    assert_instance_of Antd::PointerFinalizeResult, r
    assert_equal [A, STATE, 1, nil], [r.address, r.state_id, r.counter, r.finality]
  end

  def test_pointer_finalize_transfer_carries_finality
    stub_json(:post, "/v1/pointers/finalize",
              { address: A, state_id: STATE, counter: MAX, finality: finality_json(status: "settling", counter: nil) })

    r = @client.pointer_finalize("up-1", {})
    assert_equal Antd::POINTER_FINAL_COUNTER, r.counter
    assert_equal Antd::PointerFinalityStatus::SETTLING, r.finality.status
  end

  # --- counters ---

  def test_parse_pointer_counter_accepts_u64_decimals
    assert_equal 0, Antd.parse_pointer_counter("counter", "0")
    assert_equal 7, Antd.parse_pointer_counter("counter", "007")
    assert_equal 2**64 - 1, Antd.parse_pointer_counter("counter", MAX)
  end

  # Integer() alone would take a sign, underscores or a radix prefix; none
  # of these, nor anything past u64, may read as a counter (or as 0).
  def test_parse_pointer_counter_rejects_anything_else
    ["", " 1", "1 ", "1\n", "+1", "-1", "1_000", "0x10", "0b1", "1.0", "1e3", "１",
     "18446744073709551616", "99999999999999999999999", 1, 0, nil, true].each do |bad|
      err = assert_raises(Antd::InternalError, bad.inspect) { Antd.parse_pointer_counter("counter", bad) }
      assert_includes err.message, "counter", bad.inspect
    end
  end

  def test_malformed_counter_is_an_error_not_zero
    stub_json(:get, "/v1/pointers/#{A}", record_json(counter: "not-a-number"))
    assert_raises(Antd::InternalError) { @client.pointer_get(A) }

    stub_json(:post, "/v1/pointers", { address: A, state_id: STATE, counter: 0 })
    assert_raises(Antd::InternalError) { @client.pointer_create(A, T1) }
  end

  # --- errors ---

  def test_pointer_final_is_not_already_exists
    stub_error(409, "POINTER_FINAL", "Pointer is final: transferred")
    err = assert_raises(Antd::PointerFinalError) { @client.pointer_update(A, T1) }
    refute_kind_of Antd::AlreadyExistsError, err
    assert_equal 409, err.status_code
    assert_includes err.message, "Pointer is final"
  end

  def test_pointer_forked_is_a_fork_error
    stub_error(409, "POINTER_FORKED", "Pointer is forked: two final states")
    err = assert_raises(Antd::PointerForkedError) { @client.pointer_update(A, T1) }
    assert_kind_of Antd::ForkError, err
    refute_kind_of Antd::AlreadyExistsError, err
    assert_equal 409, err.status_code
  end

  def test_conflict_is_not_already_exists
    stub_error(409, "CONFLICT", "Conflict: a prepared write awaits payment")
    err = assert_raises(Antd::ConflictError) { @client.pointer_update(A, T1) }
    refute_kind_of Antd::AlreadyExistsError, err
    assert_equal 409, err.status_code
  end

  def test_already_exists_keeps_its_mapping
    stub_error(409, "ALREADY_EXISTS", "Already exists: pointer")
    assert_raises(Antd::AlreadyExistsError) { @client.pointer_create(A, T1) }

    stub_request(:post, "#{BASE}/v1/pointers").to_return(status: 409, body: "conflict")
    assert_raises(Antd::AlreadyExistsError) { @client.pointer_create(A, T1) }
  end

  def test_close_group_shortfall_retryable_only_when_true
    { true => true, false => false, nil => false, "true" => false, 1 => false }.each do |sent, retryable|
      body = { error: "Close group shortfall: stored on 4 of 5", code: "CLOSE_GROUP_SHORTFALL" }
      body[:retryable] = sent unless sent.nil?
      stub_request(:post, "#{BASE}/v1/pointers/finalize").to_return(status: 503, body: body.to_json)

      err = assert_raises(Antd::CloseGroupShortfallError, sent.inspect) { @client.pointer_finalize("up-1", {}) }
      assert_equal retryable, err.retryable, sent.inspect
      assert_equal retryable, err.retryable?, sent.inspect
      assert_equal 503, err.status_code
      refute_kind_of Antd::ServiceUnavailableError, err
    end
  end

  # Any call can meet a shortfall, not only the pointer methods.
  def test_close_group_shortfall_on_a_read_and_a_chunk_put
    stub_error(503, "CLOSE_GROUP_SHORTFALL", "Close group shortfall: only 3 answered", method: :get)
    err = assert_raises(Antd::CloseGroupShortfallError) { @client.pointer_get(A) }
    refute err.retryable

    stub_error(503, "CLOSE_GROUP_SHORTFALL", "Close group shortfall", path: "/v1/chunks")
    assert_raises(Antd::CloseGroupShortfallError) { @client.chunk_put("x") }
  end

  def test_a_plain_503_stays_service_unavailable
    stub_error(503, "SERVICE_UNAVAILABLE", "wallet not configured")
    err = assert_raises(Antd::ServiceUnavailableError) { @client.pointer_create(A, T1) }
    refute_kind_of Antd::CloseGroupShortfallError, err
  end

  def test_unknown_owner_is_bad_request
    stub_error(400, "BAD_REQUEST", "Bad request: no pointer key loaded for owner")
    assert_raises(Antd::BadRequestError) { @client.pointer_create(A, T1) }
  end

  # --- gRPC trailer mapping (pure; runs without the grpc gem) ---

  def test_grpc_metadata_maps_tags_that_agree_with_the_status_code
    md = ->(tag) { { "x-antd-error-code" => tag } }
    assert_instance_of Antd::PointerFinalError, Antd.error_for_grpc_metadata(9, "d", "m", md.call("POINTER_FINAL"))
    assert_instance_of Antd::PointerForkedError, Antd.error_for_grpc_metadata(9, "d", "m", md.call("POINTER_FORKED"))
    assert_instance_of Antd::ConflictError, Antd.error_for_grpc_metadata(10, "d", "m", md.call("CONFLICT"))
    err = Antd.error_for_grpc_metadata(14, "d", "m", md.call("CLOSE_GROUP_SHORTFALL"))
    assert_instance_of Antd::CloseGroupShortfallError, err
    refute err.retryable
    # Repeated keys arrive as an array.
    assert_instance_of Antd::ConflictError, Antd.error_for_grpc_metadata(10, "d", "m", { "x-antd-error-code" => ["CONFLICT"] })
  end

  def test_grpc_metadata_ignores_untrusted_or_missing_tags
    md = ->(tag) { { "x-antd-error-code" => tag } }
    assert_nil Antd.error_for_grpc_metadata(9, "d", "m", {})
    assert_nil Antd.error_for_grpc_metadata(9, "d", "m", nil)
    assert_nil Antd.error_for_grpc_metadata(10, "d", "m", md.call("POINTER_FINAL"))
    assert_nil Antd.error_for_grpc_metadata(9, "d", "m", md.call("CONFLICT"))
    assert_nil Antd.error_for_grpc_metadata(13, "d", "m", md.call("CLOSE_GROUP_SHORTFALL"))
    assert_nil Antd.error_for_grpc_metadata(9, "d", "m", md.call("SOMETHING_NEW"))
    assert_nil Antd.error_for_grpc_metadata(6, "d", "m", md.call("ALREADY_EXISTS"))
  end

  # retryable comes from the "(paid attempt retained...)" hint that closes
  # the details, as the daemon writes it for a retained pointer finalize.
  def test_grpc_shortfall_retryable_from_the_closing_hint
    retained = "Close group shortfall: stored on 4 of 5 (paid attempt retained: call finalize again " \
               "with the same upload_id to store it against the same payment)"
    {
      retained => true,
      "Close group shortfall: only 3 answered" => false,
      "#{retained} trailing" => false,
      "Close group shortfall: (paid attempt retai" => false,
      "peer said (paid attempt retained) (connection reset)" => false
    }.each do |details, retryable|
      err = Antd.error_for_grpc_metadata(14, details, "14:#{details}", { "x-antd-error-code" => "CLOSE_GROUP_SHORTFALL" })
      assert_equal retryable, err.retryable, details
    end
  end

  private

  def stub_json(method, path, body)
    stub_request(method, "#{BASE}#{path}").to_return(status: 200, body: body.to_json, headers: JSON_HEADERS)
  end

  def stub_error(status, code, message, method: :post, path: nil)
    path ||= method == :post ? nil : "/v1/pointers/#{A}"
    url = path ? "#{BASE}#{path}" : %r{\A#{Regexp.escape(BASE)}/v1/pointers}
    stub_request(method, url).to_return(status: status, body: { error: message, code: code }.to_json)
  end

  def record_json(counter:, is_final: false, transferred_to: nil, kind: "chunk", kind_tag: 0, target: T1)
    {
      address: A, owner: "c" * 3904, counter: counter, kind: kind, kind_tag: kind_tag,
      target: target, state_id: STATE, is_final: is_final, transferred_to: transferred_to
    }
  end

  def final_state_json(target:, kind: "chunk", kind_tag: 0, holders: 7, transferred_to: nil)
    { state_id: STATE, kind: kind, kind_tag: kind_tag, target: target, holders: holders, transferred_to: transferred_to }
  end

  def finality_json(status:, counter:, state: nil, states: [], majority: nil, transferred_to: nil)
    {
      address: A, group: 7, answered: 7, status: status, counter: counter,
      state: state, states: states, majority: majority, transferred_to: transferred_to
    }
  end

  def prepare_json(op: "update", counter: "1", signed_quotes: nil)
    body = {
      upload_id: "up-1", op: op, address: A, state_id: STATE, counter: counter,
      payment_type: "wave_batch",
      payments: [{ quote_hash: "0xq1", rewards_address: "0xr1", amount: "10" }],
      total_amount: "10", payment_vault_address: "0xvault", payment_token_address: "0xtoken",
      rpc_url: "http://localhost:8545"
    }
    body[:signed_quotes] = signed_quotes unless signed_quotes.nil?
    body
  end
end
