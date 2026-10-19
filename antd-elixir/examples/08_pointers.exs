Mix.install([
  {:antd, path: ".."}
])

# Example 08: Pointers — a mutable, owner-signed reference to data.
#
# A pointer's address is derived from its owner's key and never changes; the
# owner can point it at new data. The daemon holds the owner keys (loaded with
# `antd --pointer-keys <file-or-dir>`, key files from `ant pointer keygen`), so
# a write names the pointer by its address and no key crosses the API.
#
# Every pointer write pays (about the price of one chunk), and every attempt
# pays again: the SDK never retries a write, and neither should callers.
#
# Prerequisites: antd with a wallet and a loaded pointer key.
#
#   ANTD_POINTER_OWNER  address of a pointer the daemon holds the key for
#                       (Antd.Client.pointer_keys/1 lists them)
#   ANTD_BASE_URL       the daemon's REST URL (default http://localhost:8082)

owner =
  System.get_env("ANTD_POINTER_OWNER") ||
    raise "set ANTD_POINTER_OWNER to a pointer address the daemon holds the key for"

client = Antd.Client.new(System.get_env("ANTD_BASE_URL", "http://localhost:8082"))

# 1. Two small pieces of public data to point at.
first = Antd.Client.data_put_public!(client, "Hello from pointer version 1").address
second = Antd.Client.data_put_public!(client, "Hello from pointer version 2").address
IO.puts("Stored version 1 at #{first}")
IO.puts("Stored version 2 at #{second}")

# 2. Create the pointer at the first. A pointer that already exists is moved
#    with pointer_update instead (a second create is AlreadyExistsError,
#    refused before anything is paid).
#    (`is_struct/2` rather than a `%Antd.AlreadyExistsError{}` pattern: the
#    script is compiled before Mix.install has loaded the SDK.)
case Antd.Client.pointer_create(client, owner, first) do
  {:ok, w} ->
    IO.puts("Created pointer #{w.address} (counter #{w.counter})")

  {:error, error} ->
    unless is_struct(error, Antd.AlreadyExistsError), do: raise(error)
    w = Antd.Client.pointer_update!(client, owner, first)

    IO.puts(
      "Pointer #{w.address} already existed; pointed it at version 1 (counter #{w.counter})"
    )
end

# 3. Update it to the second.
w = Antd.Client.pointer_update!(client, owner, second)
IO.puts("Updated pointer to version 2 (counter #{w.counter})")

# 4. Read it back: the record, and the data at the end of the chain.
record = Antd.Client.pointer_get!(client, owner)

IO.puts(
  "Pointer #{record.address}: counter #{record.counter}, #{record.kind} -> #{record.target}"
)

resolved = Antd.Client.pointer_resolve!(client, owner)
data = Antd.Client.data_get_public!(client, resolved.target)
IO.puts("Resolves to #{resolved.target}: #{inspect(data)}")

unless resolved.target == second and data == "Hello from pointer version 2",
  do: raise("pointer does not resolve to version 2")

# 5. Where the whole close group says it stands. Only status :final means a
#    transfer is beyond dispute; an updatable pointer is :open.
f = Antd.Client.pointer_finality!(client, owner)

IO.puts(
  "Finality: #{inspect(f.status)} (#{f.answered}/#{f.group} peers answered, " <>
    "counter #{inspect(f.counter)})"
)

IO.puts("Pointer round-trip OK!")
