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
  @moduledoc "Daemon cannot reach the network (HTTP 502)."

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
  A finalize stored some chunks while others stayed unstored after the
  daemon's retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`; gRPC `ABORTED`).

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
    * `false` — nothing was retained (a merkle finalize with deliberately
      unpaid batches, or an older daemon). Re-preparing the same content
      skips already-stored chunks, so a retry pays only for the remainder.

  Over REST the counts and `retryable` come from the structured error body.
  Over gRPC they are parsed best-effort from the status message
  (`Partial upload: S/T chunks stored, F failed ...`, with a
  `paid attempt retained` hint when retryable); an unrecognised message
  leaves the counts `0` and `retryable` `false`.

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

  # Message tail the daemon appends to a `PARTIAL_UPLOAD` error when it kept
  # the paid attempt for a same-`upload_id` retry.
  @partial_upload_retained_hint "paid attempt retained"

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
  daemons older than 0.14.0 and defaults to `false`.
  """
  @spec partial_upload_error(integer(), map()) :: Antd.PartialUploadError.t()
  def partial_upload_error(status_code, body) when is_map(body) do
    %Antd.PartialUploadError{
      message: Map.get(body, "error", Jason.encode!(body)),
      status_code: status_code,
      chunks_stored: count(body["chunks_stored"]),
      chunks_failed: count(body["chunks_failed"]),
      total_chunks: count(body["total_chunks"]),
      retryable: body["retryable"] == true
    }
  end

  @doc """
  Builds an `Antd.PartialUploadError` from a gRPC `ABORTED` status message.
  The status carries no structured detail, so the counts and the retained
  hint are recovered from the text via `parse_partial_upload_message/1`.
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
  ...`). Returns `{chunks_stored, chunks_failed, total_chunks, retryable}`;
  an unrecognised message yields `{0, 0, 0, false}`.
  """
  @spec parse_partial_upload_message(String.t()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), boolean()}
  def parse_partial_upload_message(message) when is_binary(message) do
    {stored, failed, total} =
      case Regex.run(~r/Partial upload: (\d+)\/(\d+) chunks stored, (\d+) failed/, message) do
        [_, stored, total, failed] ->
          {String.to_integer(stored), String.to_integer(failed), String.to_integer(total)}

        nil ->
          {0, 0, 0}
      end

    {stored, failed, total, String.contains?(message, @partial_upload_retained_hint)}
  end

  defp count(n) when is_integer(n) and n >= 0, do: n
  defp count(_), do: 0
end
