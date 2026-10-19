defmodule Antd.AntdError do
  @moduledoc "Base error for all antd errors."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.BadRequestError do
  @moduledoc "Invalid request parameters (HTTP 400)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.PaymentError do
  @moduledoc "Insufficient funds or payment failure (HTTP 402)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.NotFoundError do
  @moduledoc "Resource not found on the network (HTTP 404)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.AlreadyExistsError do
  @moduledoc "Resource already exists (HTTP 409)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.ForkError do
  @moduledoc """
  Version conflict or fork detected (HTTP 409).

  A pointer whose owner signed two different final states, with no majority
  on either, is reported as a `ForkError` (HTTP 409 with
  `code: "POINTER_FORKED"`; gRPC `FAILED_PRECONDITION` tagged
  `x-antd-error-code: POINTER_FORKED`).
  """

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.PointerFinalError do
  @moduledoc """
  The pointer is at its final state: it was handed over (transferred) or
  frozen, so nothing can update it or hand it over again (HTTP 409 with
  `code: "POINTER_FINAL"`; gRPC `FAILED_PRECONDITION` tagged
  `x-antd-error-code: POINTER_FINAL`). Usually refused before anything is
  paid: the daemon reads the pointer first. A write that was already paid for
  when the network refused it (the pointer became final while the write was in
  flight) keeps that payment, so read the pointer before paying again.
  """

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.ConflictError do
  @moduledoc """
  The request conflicts with the resource's current state (HTTP 409 with
  `code: "CONFLICT"`; gRPC `ABORTED` tagged `x-antd-error-code: CONFLICT`).

  For pointers, two cases share this code, and it does not say which one
  happened or whether anything was paid:

    * a write while a prepared write to the same pointer awaits payment is
      refused before paying (finalize the prepared write, or wait for it to
      expire);
    * an update that lost to a newer state while it was in flight may already
      have been paid for.

  Read the pointer again and check what was paid before submitting another
  paid write.
  """

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.CloseGroupShortfallError do
  @moduledoc """
  Too few of an address's close group answered, or took a write, for the
  result to be the network's (HTTP 503 with `code: "CLOSE_GROUP_SHORTFALL"`;
  gRPC `UNAVAILABLE` tagged `x-antd-error-code: CLOSE_GROUP_SHORTFALL`).

  Reads are free to retry; a shortfall during an update in flight or churn
  usually clears. A paid write is not, except where `retryable` is `true`: a
  pointer finalize kept the paid state, and calling `pointer_finalize` again
  with the same `upload_id` stores it against the same payment. Bound that
  loop.

  Over REST `retryable` is the error body's `retryable` (`true` only when it
  is JSON `true`). Over gRPC it is `true` when the status message closes with
  the daemon's `(paid attempt retained...)` hint.

  This is its own exception module, not an `Antd.ServiceUnavailableError`
  (REST) or an `Antd.NetworkError` (gRPC `UNAVAILABLE`).
  """

  defexception [:message, :status_code, retryable: false]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer(),
          retryable: boolean()
        }
end

defmodule Antd.TooLargeError do
  @moduledoc "Payload too large (HTTP 413)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.InternalError do
  @moduledoc "Internal server error (HTTP 500)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.NetworkError do
  @moduledoc """
  Daemon cannot reach the network (HTTP 502).

  A 502 with `code: "PARTIAL_UPLOAD"` (some chunks stored after payment) is
  `Antd.PartialUploadError` instead, which is not a subtype of this module.
  """

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.ServiceUnavailableError do
  @moduledoc "Service unavailable, e.g. wallet not configured (HTTP 503)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
        }
end

defmodule Antd.PartialUploadError do
  @moduledoc """
  An upload stored some chunks while others stayed unstored after the
  daemon's retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`; gRPC `ABORTED`
  whose message starts with `Partial upload:`). The external-signer finalize
  functions return it, and so can daemon-wallet uploads (`data_put`,
  `file_put` and their `_public` variants): every REST and gRPC call shares
  one error mapping.

  **Error-contract change.** This is its own exception module, not a subtype
  of `Antd.NetworkError` or `Antd.AntdError`. A partial store used to come
  back as `%Antd.NetworkError{}` (REST) or `%Antd.AntdError{}` (gRPC); it now
  returns, and the bang variants raise, `%Antd.PartialUploadError{}` on both
  transports, so a clause or `rescue` that names only those modules no
  longer catches it. Add a `PartialUploadError` clause, or rescue it
  alongside them; the README's "Migrating error handlers" section has
  before/after examples. Other 502s and other `ABORTED` statuses are
  unchanged.

  The on-chain payment persists and the stored chunks stay on the network.
  How to finish the upload depends on `retryable` and `retention_known`
  (`retryable` implies `retention_known`):

    * `retryable: true` — the daemon kept the paid attempt (payment proofs
      plus the still-unstored chunks) under the same `upload_id`. Call the
      **same** finalize function again with the same `upload_id` and payment
      arguments to store the remainder against the same payment — no
      re-prepare, no second signature, no double payment. Bound that loop: a
      persistent failure returns this error on every call, so cap the
      attempts and treat a `chunks_failed` that stops shrinking as stuck.
      The retained attempt expires with the daemon's pending-upload TTL.
    * `retention_known: true, retryable: false` — the daemon confirmed it
      kept nothing (a daemon-wallet upload, or a merkle finalize with
      deliberately unpaid batches). Re-prepare the same content: stored
      chunks are skipped, so the retry pays only for the remainder.
    * `retention_known: false` — retention is unknown. The daemon may still
      hold the paid attempt (it records the resume handle before it returns
      the error), so stop automatic recovery, keep the `upload_id` and the
      original payment arguments, and reconcile before re-preparing or
      paying again. Never pay again on this signal alone. Daemons older than
      0.14.0 never send `retryable`, so their REST partial uploads read as
      unknown.

  Over REST the counts come from the structured error body, and
  `retention_known` is `true` only when the body's `retryable` is a JSON
  boolean (missing, `null` or any other type reads as unknown). Over gRPC
  they are parsed from the status message, `Partial upload: S/T chunks
  stored, F failed after retries: <reason> (<hint>)`, where the closing hint
  starts `paid attempt retained` when the daemon kept the attempt and
  `stored chunks persist; re-prepare the same content` when it did not
  (daemons older than 0.14.0 write only the second). Only a message that
  starts with the `Partial upload:` prefix is a partial upload; an `ABORTED`
  that merely quotes it further in keeps the generic `Antd.AntdError`
  mapping. `retention_known` is `true` only when the message starts with the
  counts pattern, all three counts convert (each within the daemon's `u64`
  range), and the message ends with one of the two hints; the hint then
  decides `retryable`. A pattern miss or a count that does not convert reads
  as `0` counts with both flags `false`. Readable counts with a missing,
  truncated or unrecognised hint keep the counts, but both flags stay
  `false`: retention unknown (stop and reconcile), not "nothing retained".

  See `docs/external-signer-flow.md` §6 ("Retry a partial store — same
  `upload_id`, same payment") and `finalize_with_retry/3` in
  `examples/07_external_signer.exs`.
  """

  defexception [
    :message,
    :status_code,
    chunks_stored: 0,
    chunks_failed: 0,
    total_chunks: 0,
    retryable: false,
    retention_known: false
  ]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer(),
          chunks_stored: non_neg_integer(),
          chunks_failed: non_neg_integer(),
          total_chunks: non_neg_integer(),
          retryable: boolean(),
          retention_known: boolean()
        }
end

defmodule Antd.Errors do
  @moduledoc false

  # Fixed prefix of every `PARTIAL_UPLOAD` message the daemon emits (see
  # `antd/src/error.rs`). The gRPC client treats an `ABORTED` status as a
  # partial upload only when its message starts with it.
  @partial_upload_prefix "Partial upload:"

  # The daemon closes every `PARTIAL_UPLOAD` message with one of two
  # parenthesised hints (`partial_upload_hint` in `antd/src/error.rs`): the
  # retained hint when it kept the paid attempt for a same-`upload_id` retry,
  # the not-retained hint when it did not. Daemons older than 0.14.0 write
  # only the not-retained hint. `retention_tail/1` matches exactly these two.
  @partial_upload_retained_hint "paid attempt retained"
  @partial_upload_not_retained_hint "stored chunks persist; re-prepare the same content"

  # The daemon's chunk counts are `u64`; a larger parsed value is not a count
  # it could have sent, so it fails the conversion (Elixir integers are
  # unbounded and would otherwise accept it).
  @max_count 18_446_744_073_709_551_615

  @doc "Returns the appropriate error struct for an HTTP status code."
  @spec error_for_status(integer(), String.t()) :: Exception.t()
  def error_for_status(status_code, message) do
    case status_code do
      400 -> %Antd.BadRequestError{message: message, status_code: 400}
      402 -> %Antd.PaymentError{message: message, status_code: 402}
      404 -> %Antd.NotFoundError{message: message, status_code: 404}
      409 -> %Antd.AlreadyExistsError{message: message, status_code: 409}
      413 -> %Antd.TooLargeError{message: message, status_code: 413}
      500 -> %Antd.InternalError{message: message, status_code: 500}
      502 -> %Antd.NetworkError{message: message, status_code: 502}
      503 -> %Antd.ServiceUnavailableError{message: message, status_code: 503}
      _ -> %Antd.AntdError{message: message, status_code: status_code}
    end
  end

  @doc """
  Maps the daemon codes that share an HTTP status with older errors onto
  their own error structs, or returns `nil` for any other code: the 409s
  `POINTER_FINAL` (`Antd.PointerFinalError`), `POINTER_FORKED`
  (`Antd.ForkError`) and `CONFLICT` (`Antd.ConflictError`), and
  `CLOSE_GROUP_SHORTFALL`'s 503 (`Antd.CloseGroupShortfallError`, whose
  `retryable` is set only when the body's `retryable` is JSON `true`). The
  REST client reads `code` from the error body. `ALREADY_EXISTS` is not one of
  them: it keeps the status mapping (`Antd.AlreadyExistsError`).
  """
  @spec error_for_code(term(), integer(), String.t(), term()) :: Exception.t() | nil
  def error_for_code("POINTER_FINAL", status_code, message, _body),
    do: %Antd.PointerFinalError{message: message, status_code: status_code}

  def error_for_code("POINTER_FORKED", status_code, message, _body),
    do: %Antd.ForkError{message: message, status_code: status_code}

  def error_for_code("CONFLICT", status_code, message, _body),
    do: %Antd.ConflictError{message: message, status_code: status_code}

  def error_for_code("CLOSE_GROUP_SHORTFALL", status_code, message, body) do
    %Antd.CloseGroupShortfallError{
      message: message,
      status_code: status_code,
      retryable: is_map(body) and Map.get(body, "retryable") == true
    }
  end

  def error_for_code(_code, _status_code, _message, _body), do: nil

  @doc """
  Maps a gRPC status that the daemon tagged with an `x-antd-error-code`
  metadata value onto its error struct, or returns `nil`. The tag is trusted
  only when it agrees with the status code: `FAILED_PRECONDITION` (9) for
  `POINTER_FINAL` and `POINTER_FORKED`, `ABORTED` (10) for `CONFLICT`, and
  `UNAVAILABLE` (14) for `CLOSE_GROUP_SHORTFALL`. Anything else (no tag, an
  unknown tag, or a tag on another status) is `nil` and keeps the status
  mapping, so an untagged `FAILED_PRECONDITION` is still a payment error.

  gRPC carries no structured detail, so a shortfall's `retryable` is `true`
  only when the message closes with the daemon's `(paid attempt retained...)`
  hint, which a pointer finalize that kept the paid state appends.
  """
  @spec grpc_tagged_error(integer(), term(), String.t()) :: Exception.t() | nil
  def grpc_tagged_error(9, "POINTER_FINAL", message),
    do: %Antd.PointerFinalError{message: message, status_code: 409}

  def grpc_tagged_error(9, "POINTER_FORKED", message),
    do: %Antd.ForkError{message: message, status_code: 409}

  def grpc_tagged_error(10, "CONFLICT", message),
    do: %Antd.ConflictError{message: message, status_code: 409}

  def grpc_tagged_error(14, "CLOSE_GROUP_SHORTFALL", message) do
    %Antd.CloseGroupShortfallError{
      message: message,
      status_code: 503,
      retryable: retained_hint_closes?(message)
    }
  end

  def grpc_tagged_error(_status, _tag, _message), do: nil

  # Whether the message ends with the daemon's "(paid attempt retained...)"
  # hint. Anchored at the end like `retention_tail/1`: the hint quoted
  # inside the reason is not the daemon's answer.
  defp retained_hint_closes?(message) when is_binary(message),
    do: Regex.match?(~r/\(paid attempt retained[^()]*\)\z/, message)

  defp retained_hint_closes?(_), do: false

  @doc """
  Builds an `Antd.PartialUploadError` from a decoded `PARTIAL_UPLOAD` REST
  error body. The counts are read from the body. `retention_known` is `true`
  only when `retryable` is present and a JSON boolean, which then sets
  `retryable`; a missing flag (daemons older than 0.14.0), `null` or any
  other type leaves both `false`: retention unknown. A malformed field never
  raises: a count that is not a non-negative integer reads as `0`, and a
  missing or non-string `error` falls back to the encoded body so `message`
  stays a string.
  """
  @spec partial_upload_error(integer(), map()) :: Antd.PartialUploadError.t()
  def partial_upload_error(status_code, body) when is_map(body) do
    {retryable, retention_known} = retention(body["retryable"])

    %Antd.PartialUploadError{
      message: body_message(body),
      status_code: status_code,
      chunks_stored: count(body["chunks_stored"]),
      chunks_failed: count(body["chunks_failed"]),
      total_chunks: count(body["total_chunks"]),
      retryable: retryable,
      retention_known: retention_known
    }
  end

  @doc """
  Whether `message` is a daemon `PARTIAL_UPLOAD` message, i.e. starts with
  the fixed `Partial upload:` prefix every such message opens with. The
  match is anchored at the start of the message, not a containment check: an
  `ABORTED` whose text merely quotes the phrase further in (a wrapped or
  relayed error) is not a partial upload. The gRPC client checks this before
  mapping an `ABORTED` status to `Antd.PartialUploadError`, so any other
  `ABORTED` keeps its generic `Antd.AntdError` mapping. A non-binary message
  is never a partial upload.
  """
  @spec partial_upload_message?(term()) :: boolean()
  def partial_upload_message?(message) when is_binary(message),
    do: String.starts_with?(message, @partial_upload_prefix)

  def partial_upload_message?(_), do: false

  @doc """
  Builds an `Antd.PartialUploadError` from a gRPC `ABORTED` status message
  that starts with the `Partial upload:` prefix (check with
  `partial_upload_message?/1` first). The status carries no structured
  detail, so the counts, `retryable` and `retention_known` are recovered from
  the text via `parse_partial_upload_message/1`. A prefixed message whose
  counts do not parse still builds the error, with zero counts and both
  flags `false` (retention unknown), even when the retained hint is present;
  readable counts without one of the daemon's two closing hints keep the
  counts, again with both flags `false`.
  """
  @spec partial_upload_error_from_message(integer(), String.t()) ::
          Antd.PartialUploadError.t()
  def partial_upload_error_from_message(status_code, message) when is_binary(message) do
    {stored, failed, total, retryable, retention_known} = parse_partial_upload_message(message)

    %Antd.PartialUploadError{
      message: message,
      status_code: status_code,
      chunks_stored: stored,
      chunks_failed: failed,
      total_chunks: total,
      retryable: retryable,
      retention_known: retention_known
    }
  end

  @doc """
  Parses the chunk counts and the daemon's retention hint out of a
  `PARTIAL_UPLOAD` message (`Partial upload: <stored>/<total> chunks stored,
  <failed> failed after retries: <reason> (<hint>)`). Returns
  `{chunks_stored, chunks_failed, total_chunks, retryable, retention_known}`.

  `retention_known` is `true` only when the message starts with the counts
  pattern, all three counts convert (each at most `u64::MAX`, the daemon's
  count type), and the message ends with one of the daemon's two hints,
  `(paid attempt retained...)` or `(stored chunks persist; re-prepare the
  same content...)`; `retryable` is then `true` only for the first. On a
  pattern miss or any failed conversion the result is
  `{0, 0, 0, false, false}`, hint or not. Readable counts with a missing,
  truncated or unrecognised tail, or text or a newline after it, keep the
  counts but leave both flags `false`; a hint quoted inside the failure
  reason is not the daemon's answer. A message the SDK could not fully read
  never advertises a retry against the same `upload_id`, nor that nothing
  was kept.
  """
  @spec parse_partial_upload_message(String.t()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), boolean(), boolean()}
  def parse_partial_upload_message(message) when is_binary(message) do
    with [_, stored, total, failed] <-
           Regex.run(~r/\APartial upload: (\d+)\/(\d+) chunks stored, (\d+) failed/, message),
         {:ok, stored} <- to_count(stored),
         {:ok, total} <- to_count(total),
         {:ok, failed} <- to_count(failed) do
      case retention_tail(message) do
        {:ok, retryable} -> {stored, failed, total, retryable, true}
        :unknown -> {stored, failed, total, false, false}
      end
    else
      _ -> {0, 0, 0, false, false}
    end
  end

  # Reads the daemon's retention hint, which must close the message:
  # `(<hint>...)` at the very end of the input. `\z`, not `$`: in PCRE `$`
  # also matches before a trailing newline. A hint quoted inside the failure
  # reason, a truncated, unclosed or unrecognised tail, or anything after the
  # closing paren does not match. Returns `{:ok, retryable}` or `:unknown`.
  defp retention_tail(message) do
    case Regex.run(
           ~r/\((paid attempt retained|stored chunks persist; re-prepare the same content)[^()]*\)\z/,
           message
         ) do
      [_, @partial_upload_retained_hint] -> {:ok, true}
      [_, @partial_upload_not_retained_hint] -> {:ok, false}
      _ -> :unknown
    end
  end

  # Converts a run of ASCII digits (guaranteed by the regex) to a count,
  # failing for a value the daemon's `u64` counts could not hold.
  defp to_count(digits) do
    case String.to_integer(digits) do
      n when n <= @max_count -> {:ok, n}
      _ -> :error
    end
  end

  defp count(n) when is_integer(n) and n >= 0, do: n
  defp count(_), do: 0

  # REST `retryable` counts only as a JSON boolean; anything else (missing on
  # daemons older than 0.14.0, null, a string, a number) leaves retention
  # unknown. Returns `{retryable, retention_known}`.
  defp retention(flag) when is_boolean(flag), do: {flag, true}
  defp retention(_), do: {false, false}

  defp body_message(%{"error" => message}) when is_binary(message), do: message
  defp body_message(body), do: Jason.encode!(body)
end
