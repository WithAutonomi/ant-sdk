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
      {:grpc, "~> 0.9"},
      {:protobuf, "~> 0.12"},
      {:bypass, "~> 2.1", only: :test}
    ]
  end
end
