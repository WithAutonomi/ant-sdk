defmodule Antd.GrpcAdapter do
  @moduledoc false

  # The gRPC client adapter `Antd.GrpcClient` connects with. It is
  # `GRPC.Client.Adapters.Gun` in every respect but one: a unary call made
  # with `return_headers: true` keeps its response metadata when it fails,
  # and returns
  #
  #     {:error, %GRPC.RPCError{}, %{headers: map, trailers: map}}
  #
  # instead of `{:error, %GRPC.RPCError{}}`, mirroring the
  # `{:ok, reply, %{headers: map, trailers: map}}` of a successful call.
  #
  # Gun's adapter returns the headers and trailers of a call that succeeded
  # but drops them from one that failed, and the daemon sends its error code
  # there (`x-antd-error-code`) for the errors that share a gRPC status with
  # older ones. `GRPC.RPCError` has no field for metadata.
  #
  # How: grpc 1.0's Gun adapter reads a call's response from a per-stream
  # `GRPC.Client.Adapters.Gun.StreamResponseProcess`, which queues the
  # stream's messages and hands them out one `await/2` at a time. This adapter
  # takes the stream's messages out of that process up to the last one of the
  # response, notes their headers and trailers, then plays them into a fresh
  # `StreamResponseProcess` (as the gun messages it was built to receive) and
  # lets Gun's own `receive_data/2` read that one. So decoding and every
  # success and error result stay Gun's.
  #
  # Calls without `return_headers`, and every server-streaming call, go to
  # Gun untouched. The SDK only sets `return_headers` on unary calls for its
  # pointer functions.
  #
  # Written against grpc 1.0.5 with gun 2.4.1. It leans on
  # `StreamResponseProcess.start_link/0`, `await/2` and the gun messages that
  # process accepts, and on the `:response_pid` key of the stream payload.
  # Re-run test/antd/grpc_pointers_test.exs on any grpc upgrade.

  @behaviour GRPC.Client.Adapter

  alias GRPC.Client.Adapters.Gun
  alias GRPC.Client.Adapters.Gun.StreamResponseProcess

  @impl true
  defdelegate connect(channel, opts), to: Gun

  @impl true
  defdelegate disconnect(channel), to: Gun

  @impl true
  defdelegate send_request(stream, message, opts), to: Gun

  @impl true
  defdelegate send_headers(stream, opts), to: Gun

  @impl true
  defdelegate send_data(stream, message, opts), to: Gun

  @impl true
  defdelegate end_stream(stream), to: Gun

  @impl true
  defdelegate cancel(stream), to: Gun

  @impl true
  def receive_data(%{server_stream: false} = stream, opts) do
    if opts[:return_headers],
      do: receive_with_metadata(stream, opts),
      else: Gun.receive_data(stream, opts)
  end

  def receive_data(stream, opts), do: Gun.receive_data(stream, opts)

  defp receive_with_metadata(stream, opts) do
    %{payload: %{response_pid: response_pid} = payload} = stream

    case collect(response_pid, await_timeout(opts[:timeout]), []) do
      {:ok, messages} ->
        {:ok, replay} = StreamResponseProcess.start_link()
        Enum.each(messages, &send(replay, &1))
        replayed = %{stream | payload: %{payload | response_pid: replay}}

        try do
          case Gun.receive_data(replayed, opts) do
            {:error, error} -> {:error, error, metadata(messages)}
            result -> result
          end
        after
          stop(replay)
        end

      {:error, _} = error ->
        error
    end
  end

  # Gun's adapter waits up to twice the call's timeout for each message.
  defp await_timeout(timeout) when is_integer(timeout), do: timeout * 2
  defp await_timeout(timeout), do: timeout

  # Takes the stream's messages until its last one: a response or data frame
  # that ends the stream, its trailers, or an error. Each comes back as the
  # gun message that produced it, for a StreamResponseProcess to queue again.
  # A dead stream process answers with a connection error, which Gun reports.
  defp collect(response_pid, timeout, acc) do
    case StreamResponseProcess.await(response_pid, timeout) do
      {:response, fin, status, headers} ->
        next(response_pid, timeout, acc, fin, {:gun_response, nil, nil, fin, status, headers})

      {:data, fin, data} ->
        next(response_pid, timeout, acc, fin, {:gun_data, nil, nil, fin, data})

      {:trailers, trailers} ->
        {:ok, Enum.reverse([{:gun_trailers, nil, nil, trailers} | acc])}

      {:error, :timeout} ->
        # What Gun's adapter answers when the server does not reply in time.
        {:error,
         GRPC.RPCError.exception(
           GRPC.Status.deadline_exceeded(),
           "timeout when waiting for server"
         )}

      {:error, {:stream_error, reason}} ->
        {:ok, Enum.reverse([{:gun_error, nil, nil, reason} | acc])}

      {:error, {:connection_error, reason}} ->
        {:ok, Enum.reverse([{:gun_error, nil, reason} | acc])}

      {:error, {:unexpected_message, _}} = unexpected ->
        {:ok, Enum.reverse([unexpected | acc])}
    end
  end

  defp next(_response_pid, _timeout, acc, :fin, message), do: {:ok, Enum.reverse([message | acc])}
  defp next(response_pid, timeout, acc, :nofin, message), do: collect(response_pid, timeout, [message | acc])

  defp stop(pid) do
    GenServer.stop(pid)
  catch
    :exit, _ -> :ok
  end

  defp metadata(messages) do
    Enum.reduce(messages, %{headers: %{}, trailers: %{}}, fn
      {:gun_response, _, _, _, _, headers}, acc ->
        %{acc | headers: GRPC.Transport.HTTP2.decode_headers(headers)}

      {:gun_trailers, _, _, trailers}, acc ->
        %{acc | trailers: GRPC.Transport.HTTP2.decode_headers(trailers)}

      _, acc ->
        acc
    end)
  end
end
