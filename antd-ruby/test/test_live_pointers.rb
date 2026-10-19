# frozen_string_literal: true

# Live pointer round trip against a running antd with a devnet behind it.
#
# Skipped unless all three are set:
#
# - ANTD_TEST_URL: the daemon's REST base URL, e.g. http://127.0.0.1:8082
# - ANTD_TEST_GRPC: its gRPC target, e.g. 127.0.0.1:50051
# - ANTD_TEST_POINTER_OWNERS: two comma-separated pointer addresses the
#   daemon holds keys for (antd --pointer-keys) and that have never been
#   written. The test creates both, hands the first over to the second, and
#   leaves the second with a prepared write awaiting payment, so each pair
#   can be used once.
#
# Every write is paid by the daemon's wallet, so run it against a devnet:
#
#   ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_GRPC=127.0.0.1:50051 \
#   ANTD_TEST_POINTER_OWNERS=<hex>,<hex> \
#   bundle exec ruby -Ilib -Itest test/test_live_pointers.rb

require "minitest/autorun"
require_relative "../lib/antd"

class TestLivePointers < Minitest::Test
  def test_live_pointer_round_trip
    url = ENV.fetch("ANTD_TEST_URL", "")
    target = ENV.fetch("ANTD_TEST_GRPC", "")
    owners = ENV.fetch("ANTD_TEST_POINTER_OWNERS", "").split(",").map { |o| norm(o) }
    if url.empty? || target.empty? || owners.length != 2 || owners.any?(&:empty?)
      skip "set ANTD_TEST_URL, ANTD_TEST_GRPC and ANTD_TEST_POINTER_OWNERS to run the live pointer test"
    end
    skip "needs the grpc gem" unless defined?(Antd::GrpcClient) && Antd::GrpcClient.method_defined?(:pointer_get)

    a, b = owners
    rest = Antd::Client.new(base_url: url)
    grpc = Antd::GrpcClient.new(target: target)

    # Both owners must be writable through this daemon.
    keys = rest.pointer_keys.map { |k| norm(k) }
    assert_includes keys, a, "daemon holds no key for #{a}"
    assert_includes keys, b, "daemon holds no key for #{b}"
    assert_equal keys.sort, grpc.pointer_keys.map { |k| norm(k) }.sort

    # Real targets, so the chain can be followed back to bytes.
    one = rest.data_put_public("antd-ruby pointer target one").address
    two = rest.data_put_public("antd-ruby pointer target two").address

    # -- REST: create, read, update --
    assert_raises(Antd::NotFoundError, "owner #{a} has been written before; use a fresh pair") { rest.pointer_get(a) }
    w = rest.pointer_create(a, one)
    assert_equal [a, 0], [norm(w.address), w.counter]
    assert_raises(Antd::AlreadyExistsError) { rest.pointer_create(a, two) }

    r = rest.pointer_get(a)
    assert_equal [0, one, false, nil], [r.counter, r.target, r.is_final, r.transferred_to]
    assert_equal Antd::PointerKind::CHUNK, r.target_kind
    assert_equal 2 * 1952, r.owner.length
    res = rest.pointer_resolve(a)
    assert_equal one, res.target
    assert_equal "antd-ruby pointer target one", rest.data_get_public(res.target)

    w = rest.pointer_update(a, two)
    assert_equal 1, w.counter
    assert_equal two, rest.pointer_resolve(a).target
    f = rest.pointer_finality(a)
    assert_equal [Antd::PointerFinalityStatus::OPEN, 1, nil, nil], [f.status, f.counter, f.state, f.transferred_to]
    assert_equal f.group, f.answered

    # -- gRPC: the same finality (unset fields as nil), then a write and a read --
    f = grpc.pointer_finality(a)
    assert_equal [Antd::PointerFinalityStatus::OPEN, 1, nil, nil], [f.status, f.counter, f.state, f.transferred_to]
    w = grpc.pointer_create(b, one, kind: Antd::PointerKind::CHUNK)
    assert_equal 0, w.counter
    r = grpc.pointer_get(b)
    assert_equal [0, one, nil], [r.counter, r.target, r.transferred_to]

    # -- transfer a -> b --
    t = rest.pointer_transfer(a, b)
    refute_nil t.finality, "the close group should answer after the transfer: #{t.finality_error}"
    assert t.finality.final?
    assert_equal b, norm(t.finality.transferred_to)
    r = rest.pointer_get(a)
    assert r.final?
    assert_equal Antd::POINTER_FINAL_COUNTER, r.counter
    assert_equal b, norm(r.transferred_to)
    c = rest.pointer_controller(a)
    assert_equal [b, [b], false], [norm(c.pointer), c.transfers.map { |x| norm(x) }, c.frozen]
    # a now resolves through b.
    assert_equal one, grpc.pointer_resolve(a).target
    r = grpc.pointer_get(a)
    assert_equal [Antd::POINTER_FINAL_COUNTER, true, b], [r.counter, r.is_final, norm(r.transferred_to)]
    assert grpc.pointer_finality(a).final?

    # A final pointer refuses every write, before anything is paid.
    assert_raises(Antd::PointerFinalError) { rest.pointer_update(a, one) }
    assert_raises(Antd::PointerFinalError) { grpc.pointer_update(a, one) }
    assert_raises(Antd::PointerFinalError) { rest.pointer_transfer(a, b) }

    # -- external signer, up to the quote --
    # Last: the prepared write blocks b's other writes until it expires.
    p = rest.pointer_prepare(b, Antd::PointerOp::UPDATE, target: two, include_signed_quotes: true)
    assert_equal ["update", 1, "wave_batch"], [p.op, p.counter, p.payment_type]
    refute_empty p.upload_id
    refute_empty p.payments
    assert_equal p.payments.map(&:quote_hash).sort, p.signed_quotes.map(&:quote_hash).sort
    assert_raises(Antd::ConflictError) { rest.pointer_update(b, two) }
    assert_raises(Antd::ConflictError) { grpc.pointer_prepare(b, Antd::PointerOp::UPDATE, target: two) }
    # A finalize without the payment is refused and keeps the session.
    assert_raises(Antd::BadRequestError) { rest.pointer_finalize(p.upload_id, {}) }
    assert_raises(Antd::ConflictError) { rest.pointer_update(b, two) }
  end

  private

  # The daemon accepts a 0x prefix but returns bare hex.
  def norm(address)
    address.to_s.strip.downcase.delete_prefix("0x")
  end
end
