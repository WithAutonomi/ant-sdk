# frozen_string_literal: true

require "minitest/autorun"
# Loads the helpers only: the example's script body is guarded to run when the
# file is executed directly, and needs the eth gem and a live daemon.
require_relative "../examples/07_external_signer"

# Direct tests for the example's finalize_with_retry helper against a scripted
# client: resume with unchanged arguments, exhaustion, stalled progress,
# confirmed vs unknown retention (including from gRPC status text), and
# interruption.
class TestExampleFinalizeWithRetry < Minitest::Test
  TX = { "0xq1" => "0xt1" }.freeze
  NO_WAIT = ->(_attempt) {}

  # Serves finalize_upload from a scripted list (a result, or an error to
  # raise) and records every call. It defines nothing else: any prepare or
  # payment call from the helper would raise NoMethodError.
  class ScriptedClient
    attr_reader :calls

    def initialize(*outcomes)
      @outcomes = outcomes
      @calls = []
    end

    def finalize_upload(upload_id, tx_hashes)
      @calls << [upload_id, tx_hashes]
      raise "unexpected finalize call ##{@calls.length}" if @outcomes.empty?

      outcome = @outcomes.shift
      raise outcome if outcome.is_a?(Exception)

      outcome
    end
  end

  def test_resumes_with_unchanged_arguments_until_complete
    done = Object.new
    client = ScriptedClient.new(partial(300, 12), partial(308, 4), done)
    waits = []
    result = nil
    capture_io { result = finalize_with_retry(client, "u1", TX, backoff: ->(a) { waits << a }) }

    assert_same done, result
    assert_equal 3, client.calls.length
    client.calls.each do |upload_id, tx_hashes|
      assert_equal "u1", upload_id
      assert_same TX, tx_hashes # the same payment artefacts on every call
    end
    assert_equal [1, 2], waits
  end

  def test_stalled_progress_stops_with_the_retained_attempt
    client = ScriptedClient.new(partial(300, 12), partial(300, 12), Object.new)
    err = nil
    capture_io do
      err = assert_raises(Antd::PartialUploadError) { finalize_with_retry(client, "u1", TX, backoff: NO_WAIT) }
    end

    assert_equal 2, client.calls.length
    assert_includes err.message, "stuck after 2 attempt(s)"
    assert_includes err.message, "upload_id u1"
    # The daemon still holds the paid attempt: re-preparing would pay again.
    assert_includes err.message, "retry the same finalize later (don't re-prepare, which would pay again)"
    assert err.retryable
    assert err.retention_known
    assert_equal [300, 12, 312], [err.chunks_stored, err.chunks_failed, err.total_chunks]
  end

  def test_exhaustion_caps_the_attempts
    shrinking = (0...8).map { |i| partial(300 + i, 12 - i) }
    [5, 2].each do |cap|
      client = ScriptedClient.new(*shrinking)
      err = nil
      capture_io do
        err = assert_raises(Antd::PartialUploadError) do
          finalize_with_retry(client, "u1", TX, max_attempts: cap, backoff: NO_WAIT)
        end
      end
      assert_equal cap, client.calls.length
      assert_includes err.message, "stuck after #{cap} attempt(s)"
      assert err.retryable
      assert err.retention_known
    end
  end

  # Confirmed non-retention is re-raised untouched: re-preparing is the
  # caller's decision, never the helper's.
  def test_confirmed_non_retention_is_reraised_untouched
    not_kept = partial(300, 12, retryable: false, retention_known: true)
    client = ScriptedClient.new(not_kept, Object.new)
    err = assert_raises(Antd::PartialUploadError) do
      finalize_with_retry(client, "u1", TX, backoff: ->(_) { flunk "must not wait" })
    end

    assert_same not_kept, err
    assert_equal 1, client.calls.length
  end

  # Unknown retention stops at once: no retry, no re-prepare, no payment,
  # and the error names the upload_id to reconcile.
  def test_unknown_retention_stops_without_retrying
    unknown = partial(300, 12, retryable: false, retention_known: false)
    client = ScriptedClient.new(unknown, Object.new)
    err = assert_raises(Antd::PartialUploadError) do
      finalize_with_retry(client, "u1", TX, backoff: ->(_) { flunk "must not wait" })
    end

    assert_equal 1, client.calls.length
    refute err.retryable
    refute err.retention_known
    assert_same unknown, err.cause
    assert_includes err.message, "retention of the paid attempt is unknown"
    assert_includes err.message, "upload_id u1"
    assert_includes err.message, "reconcile"
    assert_equal [300, 12, 312], [err.chunks_stored, err.chunks_failed, err.total_chunks]
  end

  # An interruption during the backoff propagates as is (still an Interrupt)
  # after naming the retained upload; no further finalize call is made.
  def test_interruption_during_backoff_propagates_and_names_the_upload
    first = partial(300, 12)
    client = ScriptedClient.new(first, Object.new)
    err = nil
    _out, stderr = capture_io do
      err = assert_raises(Interrupt) do
        finalize_with_retry(client, "u1", TX, backoff: ->(_) { raise Interrupt })
      end
    end

    assert_equal 1, client.calls.length
    assert_same first, err.cause
    assert_includes stderr, "upload_id u1"
    assert_includes stderr, "300/312"
    assert_includes stderr, "do not re-prepare or pay again"
  end

  GRPC_COUNTS = "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum"

  # End to end from the gRPC status text: the SDK parser's flags must steer
  # the helper to stop and reconcile, never to the caller's re-prepare path,
  # whenever the daemon's answer on retention could not be read.
  def test_grpc_message_without_a_readable_hint_stops_to_reconcile
    [
      "", # no hint
      " (paid attempt retai", # the review's reproducer: the retained hint cut short
      " (stored chunks persist; re-prepare the same con" # the not-retained hint cut short
    ].each do |tail|
      msg = GRPC_COUNTS + tail
      unreadable = Antd::PartialUploadError.new(msg, **Antd.parse_partial_upload_message(msg))
      client = ScriptedClient.new(unreadable, Object.new)
      err = assert_raises(Antd::PartialUploadError, msg) do
        finalize_with_retry(client, "u1", TX, backoff: ->(_) { flunk "must not wait" })
      end

      assert_equal 1, client.calls.length, msg
      refute_same unreadable, err, "#{msg}: must not be re-raised as confirmed non-retention"
      refute err.retryable, msg
      refute err.retention_known, msg
      assert_includes err.message, "retention of the paid attempt is unknown", msg
      assert_includes err.message, "reconcile", msg
      assert_equal [300, 12, 312], [err.chunks_stored, err.chunks_failed, err.total_chunks], msg
    end
  end

  # Only the daemon's explicit not-retained hint reaches the caller's
  # re-prepare path (the error re-raised untouched).
  def test_grpc_message_with_the_not_retained_hint_is_confirmed_non_retention
    msg = "#{GRPC_COUNTS} (stored chunks persist; re-prepare the same content to retry only the remainder)"
    not_kept = Antd::PartialUploadError.new(msg, **Antd.parse_partial_upload_message(msg))
    client = ScriptedClient.new(not_kept, Object.new)
    err = assert_raises(Antd::PartialUploadError) do
      finalize_with_retry(client, "u1", TX, backoff: ->(_) { flunk "must not wait" })
    end

    assert_same not_kept, err
    assert err.retention_known
    refute err.retryable
    assert_equal 1, client.calls.length
  end

  def test_other_errors_pass_through_untouched
    boom = Antd::NetworkError.new("daemon unreachable")
    client = ScriptedClient.new(boom)
    err = assert_raises(Antd::NetworkError) { finalize_with_retry(client, "u1", TX, backoff: NO_WAIT) }

    assert_same boom, err
    assert_equal 1, client.calls.length
  end

  private

  def partial(stored, failed, total: 312, retryable: true, retention_known: retryable)
    Antd::PartialUploadError.new(
      "Partial upload: #{stored}/#{total} chunks stored, #{failed} failed",
      chunks_stored: stored, chunks_failed: failed, total_chunks: total,
      retryable: retryable, retention_known: retention_known
    )
  end
end
