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
  @moduledoc "Version conflict or fork detected (HTTP 409)."

  defexception [:message, :status_code]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer()
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
  How to finish the upload depends on `retryable`:

    * `true` — the daemon kept the paid attempt (payment proofs plus the
      still-unstored chunks) under the same `upload_id`. Call the **same**
      finalize function again with the same arguments to store the remainder
      against the same payment — no re-prepare, no second signature, no
      double payment. Bound that loop: a persistent failure returns this
      error on every call, so cap the attempts and treat a `chunks_failed`
      that stops shrinking as stuck. The retained attempt expires with the
      daemon's pending-upload TTL. The flag is sent by antd >= 0.14.0; older
      daemons never send it, so it reads `false` and the re-prepare path
      applies.
    * `false` — the daemon did not report keeping the attempt (a
      daemon-wallet upload, a merkle finalize with deliberately unpaid
      batches, or an older daemon). Re-preparing the same content skips
      already-stored chunks, so a retry pays only for the remainder. A
      `false` that comes from a gRPC message the SDK could not parse (all
      counts `0`) means retention is unconfirmed, not that the paid attempt
      was discarded: do not treat it alone as permission to pay again; read
      `message` (kept verbatim) and confirm first.

  Over REST the counts and `retryable` come from the structured error body.
  Over gRPC they are parsed best-effort from the status message
  (`Partial upload: S/T chunks stored, F failed ...`, with a
  `paid attempt retained` hint when retryable). Only a message that starts
  with that prefix is a partial upload; an `ABORTED` that merely quotes it
  further in keeps the generic `Antd.AntdError` mapping. `retryable` is
  `true` only when all three counts parse (each within the daemon's `u64`
  range) and the hint is present; a message whose counts do not parse reads
  as zero counts and `retryable: false`, even with the hint. That fallback
  leaves retention unconfirmed (see above), so it is not by itself a reason
  to pay again.

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
    retryable: false
  ]

  @type t :: %__MODULE__{
          message: String.t(),
          status_code: integer(),
          chunks_stored: non_neg_integer(),
          chunks_failed: non_neg_integer(),
          total_chunks: non_neg_integer(),
          retryable: boolean()
        }
end

defmodule Antd.Errors do
  @moduledoc false

  # Fixed prefix of every `PARTIAL_UPLOAD` message the daemon emits (see
  # `antd/src/error.rs`). The gRPC client treats an `ABORTED` status as a
  # partial upload only when its message starts with it.
  @partial_upload_prefix "Partial upload:"

  # Message tail the daemon appends to a `PARTIAL_UPLOAD` error when it kept
  # the paid attempt for a same-`upload_id` retry.
  @partial_upload_retained_hint "paid attempt retained"

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
  Builds an `Antd.PartialUploadError` from a decoded `PARTIAL_UPLOAD` REST
  error body. The counts are read from the body; `retryable` is absent on
  daemons older than 0.14.0 and defaults to `false`. A malformed field never
  raises: a count that is not a non-negative integer reads as `0`,
  `retryable` is `true` only for a JSON `true`, and a missing or non-string
  `error` falls back to the encoded body so `message` stays a string.
  """
  @spec partial_upload_error(integer(), map()) :: Antd.PartialUploadError.t()
  def partial_upload_error(status_code, body) when is_map(body) do
    %Antd.PartialUploadError{
      message: body_message(body),
      status_code: status_code,
      chunks_stored: count(body["chunks_stored"]),
      chunks_failed: count(body["chunks_failed"]),
      total_chunks: count(body["total_chunks"]),
      retryable: body["retryable"] == true
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
  detail, so the counts and the retained hint are recovered from the text
  via `parse_partial_upload_message/1`; a prefixed message whose counts do
  not parse still builds the error, with zero counts and `retryable: false`
  even when the retained hint is present (retention unconfirmed, not ruled
  out).
  """
  @spec partial_upload_error_from_message(integer(), String.t()) ::
          Antd.PartialUploadError.t()
  def partial_upload_error_from_message(status_code, message) when is_binary(message) do
    {stored, failed, total, retryable} = parse_partial_upload_message(message)

    %Antd.PartialUploadError{
      message: message,
      status_code: status_code,
      chunks_stored: stored,
      chunks_failed: failed,
      total_chunks: total,
      retryable: retryable
    }
  end

  @doc """
  Parses the chunk counts and the retained hint out of a `PARTIAL_UPLOAD`
  message (`Partial upload: <stored>/<total> chunks stored, <failed> failed
  ...`). Returns `{chunks_stored, chunks_failed, total_chunks, retryable}`.

  `retryable` is `true` only when the counts pattern matches, all three
  counts convert (each at most `u64::MAX`, the daemon's count type), and the
  `paid attempt retained` hint is present. On a pattern miss or any failed
  conversion the result is `{0, 0, 0, false}`, hint or not: a retry against
  the same `upload_id` is only advertised when the whole message parsed.
  That `false` means retention is unconfirmed, not that the daemon discarded
  the paid attempt.
  """
  @spec parse_partial_upload_message(String.t()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), boolean()}
  def parse_partial_upload_message(message) when is_binary(message) do
    with [_, stored, total, failed] <-
           Regex.run(~r/Partial upload: (\d+)\/(\d+) chunks stored, (\d+) failed/, message),
         {:ok, stored} <- to_count(stored),
         {:ok, total} <- to_count(total),
         {:ok, failed} <- to_count(failed) do
      {stored, failed, total, String.contains?(message, @partial_upload_retained_hint)}
    else
      _ -> {0, 0, 0, false}
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

  defp body_message(%{"error" => message}) when is_binary(message), do: message
  defp body_message(body), do: Jason.encode!(body)
end
