defmodule Antd.MixProject do
  use Mix.Project

  def project do
    [
      app: :antd,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir SDK for the antd daemon — gateway to the Autonomi network",
      source_url: "https://github.com/WithAutonomi/ant-sdk/antd-elixir"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.4"},
      {:jason, "~> 1.4"},
      # grpc < 1.0 carries the advisories GHSA-grp7-v8xh-rj7h (critical) and
      # three more, all fixed in 1.0.0. From 1.0 the client is its own package
      # and gun is an optional dependency of it, so it is listed here.
      # Antd.GrpcAdapter copies from grpc's Gun adapter internals, so keep the
      # range to one minor line and re-run test/antd/grpc_pointers_test.exs
      # when moving it.
      {:grpc, "~> 1.0.5"},
      {:gun, "~> 2.4.0"},
      {:protobuf, "~> 0.12"},
      # Only the test suite's mock servers use the server half.
      {:grpc_server, "~> 1.0.5", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end
end
