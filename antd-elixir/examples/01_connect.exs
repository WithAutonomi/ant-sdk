Mix.install([
  {:antd, path: ".."}
])

# Connect to the antd daemon and check health
client = Antd.Client.new()

case Antd.Client.health(client) do
  {:ok, health} ->
    IO.puts("Daemon healthy: #{health.ok}")
    IO.puts("Network: #{health.network}")

  {:error, error} ->
    IO.puts("Failed to connect: #{Exception.message(error)}")
    IO.puts("Make sure antd is running: ant dev start")
end
