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
  # How: the call's gun messages are taken from this process's mailbox up to
  # the last one of the response stream, their headers and trailers noted,
  # and then sent back to this process in their original order for Gun's own
  # `receive_data/2` to read, so decoding and every success and error result
  # stay Gun's. No message of the stream can arrive after its last one, so
  # re-sending them cannot reorder anything.
  #
  # Calls without `return_headers`, and every server-streaming call, go to
  # Gun untouched. The SDK only sets `return_headers` on unary calls for its
  # pointer functions.

  @behaviour GRPC.Client.Adapter

  alias GRPC.Client.Adapters.Gun

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
    %{channel: %{adapter_payload: %{conn_pid: conn_pid}}, payload: %{stream_ref: ref}} = stream

    case collect(conn_pid, ref, await_timeout(opts[:timeout])) do
      {:ok, messages} ->
        Enum.each(messages, &send(self(), &1))

        case Gun.receive_data(stream, opts) do
          {:error, error} -> {:error, error, metadata(messages)}
          result -> result
        end

      {:error, _} = error ->
        error
    end
  end

  # Gun's adapter waits up to twice the call's timeout for each message.
  defp await_timeout(timeout) when is_integer(timeout), do: timeout * 2
  defp await_timeout(timeout), do: timeout

  defp collect(conn_pid, ref, timeout) do
    mref = Process.monitor(conn_pid)

    try do
      collect(conn_pid, ref, timeout, mref, [])
    after
      Process.demonitor(mref, [:flush])
    end
  end

  # Takes the stream's messages until its last one: a response or data frame
  # that ends the stream, its trailers, or an error. An error message is kept
  # for Gun to read and map as it would have. If the connection goes down,
  # what was taken goes back and Gun reports the dead connection.
  defp collect(conn_pid, ref, timeout, mref, acc) do
    receive do
      {:gun_response, ^conn_pid, ^ref, :nofin, _status, _headers} = msg ->
        collect(conn_pid, ref, timeout, mref, [msg | acc])

      {:gun_data, ^conn_pid, ^ref, :nofin, _data} = msg ->
        collect(conn_pid, ref, timeout, mref, [msg | acc])

      {:gun_response, ^conn_pid, ^ref, :fin, _status, _headers} = msg ->
        {:ok, Enum.reverse([msg | acc])}

      {:gun_data, ^conn_pid, ^ref, :fin, _data} = msg ->
        {:ok, Enum.reverse([msg | acc])}

      {:gun_trailers, ^conn_pid, ^ref, _trailers} = msg ->
        {:ok, Enum.reverse([msg | acc])}

      {:gun_inform, ^conn_pid, ^ref, _status, _headers} = msg ->
        {:ok, Enum.reverse([msg | acc])}

      {:gun_error, ^conn_pid, ^ref, _reason} = msg ->
        {:ok, Enum.reverse([msg | acc])}

      {:gun_error, ^conn_pid, _reason} = msg ->
        {:ok, Enum.reverse([msg | acc])}

      {:DOWN, ^mref, :process, ^conn_pid, _reason} ->
        {:ok, Enum.reverse(acc)}
    after
      timeout ->
        # What Gun's adapter answers when the server does not reply in time.
        {:error,
         GRPC.RPCError.exception(
           GRPC.Status.deadline_exceeded(),
           "timeout when waiting for server"
         )}
    end
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
