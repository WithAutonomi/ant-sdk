# frozen_string_literal: true

require "json"

module Antd
  # Base error type for all antd errors.
  class AntdError < StandardError
    attr_reader :status_code

    def initialize(message, status_code:)
      @status_code = status_code
      super("antd error #{status_code}: #{message}")
    end
  end

  # Invalid request parameters (HTTP 400).
  class BadRequestError < AntdError
    def initialize(message) = super(message, status_code: 400)
  end

  # Insufficient funds or payment failure (HTTP 402).
  class PaymentError < AntdError
    def initialize(message) = super(message, status_code: 402)
  end

  # Resource not found on the network (HTTP 404).
  class NotFoundError < AntdError
    def initialize(message) = super(message, status_code: 404)
  end

  # Resource already exists (HTTP 409).
  class AlreadyExistsError < AntdError
    def initialize(message) = super(message, status_code: 409)
  end

  # Version conflict or fork detected (HTTP 409).
  class ForkError < AntdError
    def initialize(message) = super(message, status_code: 409)
  end

  # Payload too large (HTTP 413).
  class TooLargeError < AntdError
    def initialize(message) = super(message, status_code: 413)
  end

  # Internal server error (HTTP 500).
  class InternalError < AntdError
    def initialize(message) = super(message, status_code: 500)
  end

  # Daemon cannot reach the network (HTTP 502).
  class NetworkError < AntdError
    def initialize(message) = super(message, status_code: 502)
  end

  # Service unavailable, e.g. wallet not configured (HTTP 503).
  class ServiceUnavailableError < AntdError
    def initialize(message) = super(message, status_code: 503)
  end

  # A finalize stored some chunks while others remained unstored after the
  # daemon's retries (HTTP 502 with +code: "PARTIAL_UPLOAD"+; gRPC ABORTED).
  # The on-chain payment persists and the stored chunks stay on the network.
  # How to finish the upload depends on +retryable+ and +retention_known+:
  #
  # - +retryable+ (antd >= 0.14.0; implies +retention_known+): the daemon kept
  #   the paid attempt (payment proofs + unstored chunks) under the same
  #   +upload_id+. Call the same +finalize_*+ method again with the same
  #   +upload_id+ and payment artefacts to store the remainder against the
  #   same payment -- no re-prepare, no second signature, no double payment.
  #   Bound the loop: a persistent failure raises this error on every call, so
  #   cap the attempts and treat a +chunks_failed+ that stops shrinking as
  #   stuck. The retained attempt expires with the daemon's pending-upload
  #   TTL.
  # - +retention_known+ and not +retryable+: the daemon confirmed nothing was
  #   retained (a merkle finalize with deliberately unpaid batches).
  #   Re-preparing the same content skips already-stored chunks, so a retry
  #   pays only for the missing remainder.
  # - not +retention_known+: retention is unknown. The error did not say, in
  #   a form this SDK could read, whether the paid attempt was kept, and the
  #   daemon may still hold it: it records the resume handle before it
  #   returns the error. Stop automatic recovery, keep the +upload_id+ and the
  #   original payment artefacts (tx hashes, or the merkle winner pool hash),
  #   and reconcile before re-preparing or paying again. Never pay again on
  #   this signal alone. Daemons older than 0.14.0 never send +retryable+, so
  #   their REST partial uploads read as unknown.
  #
  # Over REST the counts and flags come from the structured error body; a
  # count of the wrong JSON type reads as 0, and +retention_known+ is true
  # only when the body's +retryable+ is a JSON boolean. Over gRPC they are
  # parsed best-effort from the status details ("Partial upload: S/T chunks
  # stored, F failed after retries: <reason> (<hint>)"); only an ABORTED
  # whose details start with "Partial upload:" is a partial upload.
  # +retention_known+ is true there only when the details start with the
  # counts, all three parse, and the details end with one of the daemon's two
  # hints: "(paid attempt retained...)" sets +retryable+, and "(stored chunks
  # persist; re-prepare the same content...)" means the daemon confirmed
  # nothing was retained (daemons older than 0.14.0 write only this one).
  # Counts that do not parse leave all three zero and both flags false.
  # Readable counts with a missing, truncated or unrecognised hint keep the
  # counts, but both flags stay false: retention unknown, not "nothing
  # retained".
  #
  # Subclasses +NetworkError+ because the daemon reports it as a 502: existing
  # +rescue Antd::NetworkError+ blocks keep catching it, and +status_code+ is
  # 502 on both transports. Rescue +PartialUploadError+ first to handle it
  # specifically. See docs/external-signer-flow.md section 6.
  class PartialUploadError < NetworkError
    attr_reader :chunks_stored, :chunks_failed, :total_chunks, :retryable, :retention_known

    # @param message [String]
    # @param chunks_stored [Integer] chunks confirmed stored on the network
    # @param chunks_failed [Integer] chunks still unstored after retries
    # @param total_chunks [Integer] chunks in the upload
    # @param retryable [Boolean] whether the daemon retained the paid attempt
    # @param retention_known [Boolean] whether the daemon said, in a form this
    #   SDK could read, whether it retained the paid attempt. +retryable+
    #   implies it: +retryable: true+ always yields +retention_known == true+.
    def initialize(message, chunks_stored: 0, chunks_failed: 0, total_chunks: 0, retryable: false,
                   retention_known: false)
      @chunks_stored = chunks_stored
      @chunks_failed = chunks_failed
      @total_chunks = total_chunks
      @retryable = retryable
      @retention_known = (retention_known || retryable) ? true : false
      super(message)
    end

    alias retryable? retryable
    alias retention_known? retention_known
  end

  # Fixed text every PARTIAL_UPLOAD message from the daemon opens with. Over
  # gRPC the status carries no structured code, so an ABORTED status is a
  # partial upload only when its details start with this prefix.
  PARTIAL_UPLOAD_PREFIX = "Partial upload:"

  # Fixed prefix of the daemon's PARTIAL_UPLOAD message:
  # "Partial upload: <stored>/<total> chunks stored, <failed> failed".
  # Anchored with +\A+ (start of input; +^+ would also match after a
  # newline), so counts quoted later in a garbled message are never read.
  PARTIAL_UPLOAD_COUNTS = %r{\APartial upload: (\d+)/(\d+) chunks stored, (\d+) failed}

  # The daemon closes every PARTIAL_UPLOAD message with one of two
  # parenthesised hints (partial_upload_hint in antd/src/error.rs). This one
  # opens the hint when it kept the paid attempt for a same-upload_id retry.
  PARTIAL_UPLOAD_RETAINED_HINT = "paid attempt retained"

  # This one opens the hint when it did not. Daemons older than 0.14.0 write
  # only this one.
  PARTIAL_UPLOAD_NOT_RETAINED_HINT = "stored chunks persist; re-prepare the same content"
  private_constant :PARTIAL_UPLOAD_NOT_RETAINED_HINT

  # The hint that closes the message: "(<hint>...)" at the very end. +\z+ is
  # the end of the input; Ruby's +$+ is the end of a LINE and +\Z+ allows a
  # trailing newline. A hint quoted inside the failure reason, a truncated
  # or unclosed tail, or any text after the hint does not match.
  PARTIAL_UPLOAD_RETENTION_TAIL =
    /\((#{Regexp.union(PARTIAL_UPLOAD_RETAINED_HINT, PARTIAL_UPLOAD_NOT_RETAINED_HINT).source})[^()]*\)\z/
  private_constant :PARTIAL_UPLOAD_RETENTION_TAIL

  # Largest count the daemon can send (its counts are u64). Ruby integers are
  # unbounded, so a larger digit run is treated as a failed conversion.
  PARTIAL_UPLOAD_COUNT_MAX = 18_446_744_073_709_551_615
  private_constant :PARTIAL_UPLOAD_COUNT_MAX

  # Whether a gRPC status's details are the daemon's PARTIAL_UPLOAD message.
  # Anchored: the details must start with +PARTIAL_UPLOAD_PREFIX+. A status
  # that merely quotes "Partial upload:" further into its text (an upstream
  # error wrapping one, say) is not a partial upload and must not select the
  # paid-attempt recovery path with zero counts.
  #
  # Pass +GRPC::BadStatus#details+ -- the status message exactly as the
  # daemon sent it -- not +#message+, which grpc-ruby decorates as
  # "<code>:<details>" ("10:Partial upload: ...") and so never starts with
  # the prefix.
  #
  # @param details [String, nil] gRPC status details
  # @return [Boolean]
  def self.partial_upload_message?(details)
    details.to_s.start_with?(PARTIAL_UPLOAD_PREFIX)
  end

  # Recovers the chunk counts and the retention flags from a PARTIAL_UPLOAD
  # message (over gRPC, the status details). Used for gRPC, where the status
  # carries no structured detail; REST callers get the body fields instead.
  #
  # Conservative: +retention_known+ is true only when the message starts
  # with the counts pattern ("Partial upload: <stored>/<total> chunks
  # stored, <failed> failed"), all three counts converted (each at most
  # u64::MAX, the daemon's count type), and the message ends with one of the
  # daemon's two hints, "(paid attempt retained...)" or "(stored chunks
  # persist; re-prepare the same content...)"; +retryable+ is then true only
  # for the first. On a prefix or pattern miss, or a count out of range, all
  # three counts are 0 and both flags are false. Readable counts with a
  # missing, truncated or unrecognised tail, or text after it, keep the
  # counts but leave both flags false: the daemon's answer on retention was
  # not read, so retention is unknown, never "nothing retained". A message
  # the parser cannot fully read never selects the same-upload_id retry, and
  # never reads as confirmed non-retention.
  #
  # @param message [String]
  # @return [Hash] +:chunks_stored+, +:chunks_failed+, +:total_chunks+,
  #   +:retryable+, +:retention_known+ -- splat into +PartialUploadError.new+
  def self.parse_partial_upload_message(message)
    text = message.to_s
    m = partial_upload_message?(text) && PARTIAL_UPLOAD_COUNTS.match(text)
    # The groups are ASCII digit runs, so #to_i is exact; only the range can fail.
    stored, total, failed = m && [m[1], m[2], m[3]].map(&:to_i)
    unless m && [stored, total, failed].all? { |n| n <= PARTIAL_UPLOAD_COUNT_MAX }
      return { chunks_stored: 0, chunks_failed: 0, total_chunks: 0, retryable: false, retention_known: false }
    end

    # Only the hint that closes the message is the daemon's answer.
    tail = PARTIAL_UPLOAD_RETENTION_TAIL.match(text)
    {
      chunks_stored: stored,
      chunks_failed: failed,
      total_chunks: total,
      retryable: !tail.nil? && tail[1] == PARTIAL_UPLOAD_RETAINED_HINT,
      retention_known: !tail.nil?
    }
  end

  # Maps a non-2xx REST response onto a typed error, preferring the body's
  # machine-readable +code+ over the bare HTTP status where they diverge:
  # +PARTIAL_UPLOAD+ arrives as a 502 that would otherwise read as a generic
  # +NetworkError+. Every other code keeps the status-based mapping of
  # +error_for_status+. A JSON object body's +error+ field becomes the
  # message when it is a string; otherwise (non-JSON body, a JSON value that
  # is not an object, a non-string +error+) the raw body is the message.
  #
  # Never raises on a malformed body: every field is type-checked, not
  # coerced. Only a +code+ that is exactly the string "PARTIAL_UPLOAD"
  # selects +PartialUploadError+; a count that is not a non-negative JSON
  # integer reads as 0; +retryable+ is true only for JSON +true+; and
  # +retention_known+ is true only when +retryable+ is a JSON boolean (absent
  # on daemons < 0.14.0, +null+ or any other type reads as unknown).
  #
  # @param code [Integer] HTTP status
  # @param body [String, nil] raw response body
  # @return [AntdError]
  def self.error_for_response(code, body)
    message = body.to_s
    parsed = begin
      JSON.parse(message)
    rescue JSON::ParserError
      nil # use raw body as message
    end
    parsed = nil unless parsed.is_a?(Hash)

    if parsed
      message = parsed["error"] if parsed["error"].is_a?(String)
      if parsed["code"] == "PARTIAL_UPLOAD"
        return PartialUploadError.new(
          message,
          chunks_stored: body_count(parsed["chunks_stored"]),
          chunks_failed: body_count(parsed["chunks_failed"]),
          total_chunks: body_count(parsed["total_chunks"]),
          retryable: parsed["retryable"] == true,
          # Known only when the daemon sent the flag as a JSON boolean. Absent
          # (daemons < 0.14.0), null or any other type -> unknown: the daemon
          # may still hold the paid attempt, so this is not a re-prepare signal.
          retention_known: [true, false].include?(parsed["retryable"])
        )
      end
    end

    error_for_status(code, message)
  end

  # A chunk count from a PARTIAL_UPLOAD body: a non-negative JSON integer is
  # taken as is; anything else (absent, null, string, float, boolean, array,
  # object, negative) reads as 0 rather than raising or being coerced.
  #
  # @param value [Object] parsed JSON value
  # @return [Integer]
  def self.body_count(value)
    value.is_a?(Integer) && value >= 0 ? value : 0
  end
  private_class_method :body_count

  # Returns the appropriate error type for an HTTP status code.
  def self.error_for_status(code, message)
    case code
    when 400 then BadRequestError.new(message)
    when 402 then PaymentError.new(message)
    when 404 then NotFoundError.new(message)
    when 409 then AlreadyExistsError.new(message)
    when 413 then TooLargeError.new(message)
    when 500 then InternalError.new(message)
    when 502 then NetworkError.new(message)
    when 503 then ServiceUnavailableError.new(message)
    else          AntdError.new(message, status_code: code)
    end
  end
end
