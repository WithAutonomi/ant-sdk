defmodule Antd do
  @moduledoc """
  Elixir SDK for the antd daemon — the gateway to the Autonomi decentralized network.

  This module provides convenience delegates to `Antd.Client` so you can call
  functions directly after creating a client:

      client = Antd.Client.new()
      {:ok, health} = Antd.health(client)

  All functions return `{:ok, result}` or `{:error, exception}`.
  Bang variants (e.g. `health!/1`) raise on error.

  ## Naming convention

  Private = unqualified verb. Public = `_public` suffix. See `Antd.Client`
  for full details.

  ## Quick Start

      client = Antd.Client.new()

      # Store public data
      {:ok, result} = Antd.data_put_public(client, "Hello, Autonomi!")
      IO.puts("Stored at \#{result.address}")

      # Retrieve data
      {:ok, data} = Antd.data_get_public(client, result.address)
      IO.puts("Retrieved: \#{data}")
  """

  defdelegate new(base_url \\ "http://localhost:8082", opts \\ []), to: Antd.Client
  defdelegate health(client), to: Antd.Client
  defdelegate health!(client), to: Antd.Client

  # --- Data ---
  defdelegate data_put(client, data, opts \\ []), to: Antd.Client
  defdelegate data_put!(client, data, opts \\ []), to: Antd.Client
  defdelegate data_get(client, data_map), to: Antd.Client
  defdelegate data_get!(client, data_map), to: Antd.Client
  defdelegate data_put_public(client, data, opts \\ []), to: Antd.Client
  defdelegate data_put_public!(client, data, opts \\ []), to: Antd.Client
  defdelegate data_get_public(client, address), to: Antd.Client
  defdelegate data_get_public!(client, address), to: Antd.Client
  defdelegate data_stream(client, data_map), to: Antd.Client
  defdelegate data_stream!(client, data_map), to: Antd.Client
  defdelegate data_stream_public(client, address), to: Antd.Client
  defdelegate data_stream_public!(client, address), to: Antd.Client
  defdelegate data_cost(client, data, opts \\ []), to: Antd.Client
  defdelegate data_cost!(client, data, opts \\ []), to: Antd.Client

  # --- Chunks ---
  defdelegate chunk_put(client, data), to: Antd.Client
  defdelegate chunk_put!(client, data), to: Antd.Client
  defdelegate chunk_get(client, address), to: Antd.Client
  defdelegate chunk_get!(client, address), to: Antd.Client

  # --- Files ---
  defdelegate file_put(client, path, opts \\ []), to: Antd.Client
  defdelegate file_put!(client, path, opts \\ []), to: Antd.Client
  defdelegate file_get(client, data_map, dest_path), to: Antd.Client
  defdelegate file_get!(client, data_map, dest_path), to: Antd.Client
  defdelegate file_put_public(client, path, opts \\ []), to: Antd.Client
  defdelegate file_put_public!(client, path, opts \\ []), to: Antd.Client
  defdelegate file_get_public(client, address, dest_path), to: Antd.Client
  defdelegate file_get_public!(client, address, dest_path), to: Antd.Client
  defdelegate file_cost(client, path, is_public, opts \\ []), to: Antd.Client
  defdelegate file_cost!(client, path, is_public, opts \\ []), to: Antd.Client
end
