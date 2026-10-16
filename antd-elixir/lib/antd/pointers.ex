defmodule Antd.Pointers do
  @moduledoc false

  # Response parsing shared by the REST (`Antd.Client`) and gRPC
  # (`Antd.GrpcClient`) pointer functions.
  #
  # Counters are decimal strings on both transports, because a final state
  # sits at 2^64 - 1, past what a JSON number keeps exactly in many
  # languages. Elixir integers are unbounded, so a counter becomes an
  # integer, but only from ASCII digits (no sign, whitespace or trailing
  # text, all of which `Integer.parse/1` would accept) and only up to the
  # daemon's u64 maximum. Anything else is an error, never a silent zero.
  #
  # Unset values differ by transport: REST sends `null`, gRPC an empty
  # string or an absent message. Both read as `nil`.

  @max_counter 18_446_744_073_709_551_615

  @doc "Parses a decimal u64 counter strictly."
  @spec counter(term()) :: {:ok, non_neg_integer()} | {:error, Antd.AntdError.t()}
  def counter(value) when is_binary(value) do
    with true <- Regex.match?(~r/\A[0-9]+\z/, value),
         n when n <= @max_counter <- String.to_integer(value) do
      {:ok, n}
    else
      _ -> {:error, malformed_counter(value)}
    end
  end

  def counter(value), do: {:error, malformed_counter(value)}

  @doc "Like `counter/1`, but `nil` (REST) and `\"\"` (gRPC) read as unset."
  @spec optional_counter(term()) :: {:ok, non_neg_integer() | nil} | {:error, Antd.AntdError.t()}
  def optional_counter(nil), do: {:ok, nil}
  def optional_counter(""), do: {:ok, nil}
  def optional_counter(value), do: counter(value)

  defp malformed_counter(value) do
    %Antd.AntdError{
      message: "antd: pointer counter #{inspect(value)} is not a decimal u64",
      status_code: 0
    }
  end

  # ---------------------------------------------------------------------------
  # REST (decoded JSON bodies)
  # ---------------------------------------------------------------------------

  @spec keys_from_json(map()) :: [String.t()]
  def keys_from_json(body) do
    for key <- list(body["keys"]), is_map(key), do: str(key["address"])
  end

  @spec write_from_json(map()) :: {:ok, Antd.PointerWriteResult.t()} | {:error, Exception.t()}
  def write_from_json(body) do
    with {:ok, counter} <- counter(body["counter"]) do
      {:ok,
       %Antd.PointerWriteResult{
         address: str(body["address"]),
         state_id: str(body["state_id"]),
         counter: counter
       }}
    end
  end

  @spec record_from_json(map()) :: {:ok, Antd.PointerRecord.t()} | {:error, Exception.t()}
  def record_from_json(body) do
    with {:ok, counter} <- counter(body["counter"]) do
      {:ok,
       %Antd.PointerRecord{
         address: str(body["address"]),
         owner: str(body["owner"]),
         counter: counter,
         kind: str(body["kind"]),
         kind_tag: int(body["kind_tag"]),
         target: str(body["target"]),
         state_id: str(body["state_id"]),
         is_final: body["is_final"] == true,
         transferred_to: opt_str(body["transferred_to"])
       }}
    end
  end

  @spec target_from_json(map()) :: Antd.PointerTarget.t()
  def target_from_json(body) do
    %Antd.PointerTarget{
      kind: str(body["kind"]),
      kind_tag: int(body["kind_tag"]),
      target: str(body["target"])
    }
  end

  @spec finality_from_json(map()) :: {:ok, Antd.PointerFinality.t()} | {:error, Exception.t()}
  def finality_from_json(body) do
    with {:ok, counter} <- optional_counter(body["counter"]) do
      {:ok,
       %Antd.PointerFinality{
         address: str(body["address"]),
         group: int(body["group"]),
         answered: int(body["answered"]),
         status: Antd.PointerFinality.parse_status(str(body["status"])),
         counter: counter,
         state: final_state_from_json(body["state"]),
         states: for(s <- list(body["states"]), is_map(s), do: final_state_from_json(s)),
         majority: final_state_from_json(body["majority"]),
         transferred_to: opt_str(body["transferred_to"])
       }}
    end
  end

  # An embedded finality (transfer, finalize): `null` or absent is `nil`.
  defp optional_finality_from_json(body) when is_map(body), do: finality_from_json(body)
  defp optional_finality_from_json(_), do: {:ok, nil}

  defp final_state_from_json(state) when is_map(state) do
    %Antd.PointerFinalState{
      state_id: str(state["state_id"]),
      kind: str(state["kind"]),
      kind_tag: int(state["kind_tag"]),
      target: str(state["target"]),
      holders: int(state["holders"]),
      transferred_to: opt_str(state["transferred_to"])
    }
  end

  defp final_state_from_json(_), do: nil

  @spec controller_from_json(map()) :: Antd.PointerController.t()
  def controller_from_json(body) do
    %Antd.PointerController{
      pointer: str(body["pointer"]),
      transfers: for(t <- list(body["transfers"]), is_binary(t), do: t),
      frozen: body["frozen"] == true
    }
  end

  @spec transfer_from_json(map()) ::
          {:ok, Antd.PointerTransferResult.t()} | {:error, Exception.t()}
  def transfer_from_json(body) do
    with {:ok, finality} <- optional_finality_from_json(body["finality"]) do
      {:ok,
       %Antd.PointerTransferResult{
         address: str(body["address"]),
         state_id: str(body["state_id"]),
         finality: finality,
         finality_error: opt_str(body["finality_error"])
       }}
    end
  end

  @spec prepare_from_json(map()) ::
          {:ok, Antd.PointerPrepareResult.t()} | {:error, Exception.t()}
  def prepare_from_json(body) do
    with {:ok, counter} <- counter(body["counter"]) do
      {:ok,
       %Antd.PointerPrepareResult{
         upload_id: str(body["upload_id"]),
         op: str(body["op"]),
         address: str(body["address"]),
         state_id: str(body["state_id"]),
         counter: counter,
         payment_type: str(body["payment_type"]),
         payments:
           for p <- list(body["payments"]), is_map(p) do
             %Antd.PaymentInfo{
               quote_hash: str(p["quote_hash"]),
               rewards_address: str(p["rewards_address"]),
               amount: str(p["amount"])
             }
           end,
         total_amount: str(body["total_amount"]),
         payment_vault_address: str(body["payment_vault_address"]),
         payment_token_address: str(body["payment_token_address"]),
         rpc_url: str(body["rpc_url"]),
         signed_quotes:
           for q <- list(body["signed_quotes"]), is_map(q) do
             %Antd.SignedQuoteEntry{
               quote_hash: str(q["quote_hash"]),
               quote: str(q["quote"]),
               commitment_sidecar: opt_str(q["commitment_sidecar"])
             }
           end
       }}
    end
  end

  @spec finalize_from_json(map()) ::
          {:ok, Antd.PointerFinalizeResult.t()} | {:error, Exception.t()}
  def finalize_from_json(body) do
    with {:ok, counter} <- counter(body["counter"]),
         {:ok, finality} <- optional_finality_from_json(body["finality"]) do
      {:ok,
       %Antd.PointerFinalizeResult{
         address: str(body["address"]),
         state_id: str(body["state_id"]),
         counter: counter,
         finality: finality
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # gRPC (Antd.V1.* proto structs)
  # ---------------------------------------------------------------------------

  @spec write_from_proto(Antd.V1.PointerWriteResponse.t()) ::
          {:ok, Antd.PointerWriteResult.t()} | {:error, Exception.t()}
  def write_from_proto(resp) do
    with {:ok, counter} <- counter(resp.counter) do
      {:ok,
       %Antd.PointerWriteResult{address: resp.address, state_id: resp.state_id, counter: counter}}
    end
  end

  @spec record_from_proto(Antd.V1.PointerRecord.t()) ::
          {:ok, Antd.PointerRecord.t()} | {:error, Exception.t()}
  def record_from_proto(resp) do
    with {:ok, counter} <- counter(resp.counter) do
      {:ok,
       %Antd.PointerRecord{
         address: resp.address,
         owner: resp.owner,
         counter: counter,
         kind: resp.kind,
         kind_tag: resp.kind_tag,
         target: resp.target,
         state_id: resp.state_id,
         is_final: resp.is_final,
         transferred_to: opt_str(resp.transferred_to)
       }}
    end
  end

  @spec target_from_proto(Antd.V1.PointerResolved.t()) :: Antd.PointerTarget.t()
  def target_from_proto(resp) do
    %Antd.PointerTarget{kind: resp.kind, kind_tag: resp.kind_tag, target: resp.target}
  end

  @spec finality_from_proto(Antd.V1.PointerFinality.t() | nil) ::
          {:ok, Antd.PointerFinality.t() | nil} | {:error, Exception.t()}
  def finality_from_proto(nil), do: {:ok, nil}

  def finality_from_proto(resp) do
    with {:ok, counter} <- optional_counter(resp.counter) do
      {:ok,
       %Antd.PointerFinality{
         address: resp.address,
         group: resp.group,
         answered: resp.answered,
         status: Antd.PointerFinality.parse_status(resp.status),
         counter: counter,
         state: final_state_from_proto(resp.state),
         states: Enum.map(resp.states, &final_state_from_proto/1),
         majority: final_state_from_proto(resp.majority),
         transferred_to: opt_str(resp.transferred_to)
       }}
    end
  end

  defp final_state_from_proto(nil), do: nil

  defp final_state_from_proto(state) do
    %Antd.PointerFinalState{
      state_id: state.state_id,
      kind: state.kind,
      kind_tag: state.kind_tag,
      target: state.target,
      holders: state.holders,
      transferred_to: opt_str(state.transferred_to)
    }
  end

  @spec controller_from_proto(Antd.V1.PointerController.t()) :: Antd.PointerController.t()
  def controller_from_proto(resp) do
    %Antd.PointerController{pointer: resp.pointer, transfers: resp.transfers, frozen: resp.frozen}
  end

  @spec transfer_from_proto(Antd.V1.PointerTransferResponse.t()) ::
          {:ok, Antd.PointerTransferResult.t()} | {:error, Exception.t()}
  def transfer_from_proto(resp) do
    with {:ok, finality} <- finality_from_proto(resp.finality) do
      {:ok,
       %Antd.PointerTransferResult{
         address: resp.address,
         state_id: resp.state_id,
         finality: finality,
         finality_error: opt_str(resp.finality_error)
       }}
    end
  end

  @spec prepare_from_proto(Antd.V1.PreparePointerResponse.t()) ::
          {:ok, Antd.PointerPrepareResult.t()} | {:error, Exception.t()}
  def prepare_from_proto(resp) do
    with {:ok, counter} <- counter(resp.counter) do
      {:ok,
       %Antd.PointerPrepareResult{
         upload_id: resp.upload_id,
         op: resp.op,
         address: resp.address,
         state_id: resp.state_id,
         counter: counter,
         payment_type: resp.payment_type,
         payments:
           Enum.map(resp.payments, fn p ->
             %Antd.PaymentInfo{
               quote_hash: p.quote_hash,
               rewards_address: p.rewards_address,
               amount: p.amount
             }
           end),
         total_amount: resp.total_amount,
         payment_vault_address: resp.payment_vault_address,
         payment_token_address: resp.payment_token_address,
         rpc_url: resp.rpc_url,
         signed_quotes:
           Enum.map(resp.signed_quotes, fn q ->
             %Antd.SignedQuoteEntry{
               quote_hash: q.quote_hash,
               quote: Base.encode64(q.quote),
               commitment_sidecar:
                 if(q.commitment_sidecar == "",
                   do: nil,
                   else: Base.encode64(q.commitment_sidecar)
                 )
             }
           end)
       }}
    end
  end

  @spec finalize_from_proto(Antd.V1.FinalizePointerResponse.t()) ::
          {:ok, Antd.PointerFinalizeResult.t()} | {:error, Exception.t()}
  def finalize_from_proto(resp) do
    with {:ok, counter} <- counter(resp.counter),
         {:ok, finality} <- finality_from_proto(resp.finality) do
      {:ok,
       %Antd.PointerFinalizeResult{
         address: resp.address,
         state_id: resp.state_id,
         counter: counter,
         finality: finality
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Field helpers
  # ---------------------------------------------------------------------------

  defp str(value) when is_binary(value), do: value
  defp str(_), do: ""

  defp opt_str(value) when is_binary(value) and value != "", do: value
  defp opt_str(_), do: nil

  defp int(value) when is_integer(value) and value >= 0, do: value
  defp int(_), do: 0

  defp list(value) when is_list(value), do: value
  defp list(_), do: []
end
