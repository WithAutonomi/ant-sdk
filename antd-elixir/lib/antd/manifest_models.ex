defmodule Antd.ManifestEntryInput do
  @moduledoc """
  One file for `Antd.Client.build_manifest/3` and
  `Antd.GrpcClient.build_manifest/3`.

  Set exactly one of `data_map` or `address`; an entry with both or neither
  is refused before anything is sent (`Antd.BadRequestError`).

    * `path` — the relative path the entry extracts under, subject to the
      portable path rules. `nil` (or `""`): it extracts under its content
      address.
    * `size` — the plaintext size to record, as given (the creator's claim).
      `nil`: none is recorded, and readers take the exact size from an
      embedded root DataMap.
    * `data_map` — a hex DataMap, as the upload functions return it. The
      entry embeds it: the manifest is the key to the file.
    * `address` — a public file's DataMap address (hex, 32 bytes).
    * `sha256` — the plaintext's SHA-256 (hex) to record for the entry, passed
      through as given; the daemon validates it. `nil` (or `""`): none is
      sent. Requires antd 0.17.0 or later.

  ## Examples

      %Antd.ManifestEntryInput{path: "notes/one.txt", address: address}
      %Antd.ManifestEntryInput{path: "secret.txt", size: 82, data_map: data_map}
  """

  defstruct path: nil, size: nil, data_map: nil, address: nil, sha256: nil

  @type t :: %__MODULE__{
          path: String.t() | nil,
          size: non_neg_integer() | nil,
          data_map: String.t() | nil,
          address: String.t() | nil,
          sha256: String.t() | nil
        }
end

defmodule Antd.ManifestEntryInfo do
  @moduledoc """
  What a manifest says about one entry.

    * `effective_name` — `path`, or the content address in hex when there is
      none.
    * `path` — the entry's path, or `nil`.
    * `size` — the size recorded in the manifest (the creator's claim), or
      `nil` when none was recorded. Never `0` for "unset".
    * `kind` — `"embedded"` (the manifest carries the DataMap) or `"public"`
      (it carries a public DataMap address).
    * `content_address` — hex. The file's public DataMap address, whether or
      not it was ever made public; the same for private and public uploads of
      one file.
    * `data_map` — the embedded DataMap, in the hex form the download
      functions accept. Decode only; `nil` for public entries and in a build
      result.
    * `exact_size` — the exact plaintext size, from an embedded root DataMap
      or after a resolving decode; `nil` when unknown.
    * `error` — why a resolving decode failed for this entry, or `nil`. One
      entry's failure is reported here, not as a failed call.
    * `sha256` — the plaintext's SHA-256 (lowercase hex) the manifest records
      for the entry, or `nil` when none. Requires antd 0.17.0 or later.
  """

  defstruct effective_name: "",
            path: nil,
            size: nil,
            kind: "",
            content_address: "",
            data_map: nil,
            exact_size: nil,
            error: nil,
            sha256: nil

  @type t :: %__MODULE__{
          effective_name: String.t(),
          path: String.t() | nil,
          size: non_neg_integer() | nil,
          kind: String.t(),
          content_address: String.t(),
          data_map: String.t() | nil,
          exact_size: non_neg_integer() | nil,
          error: String.t() | nil,
          sha256: String.t() | nil
        }
end

defmodule Antd.BuiltManifest do
  @moduledoc """
  The result of `build_manifest`.

    * `manifest` — the `.ant` bytes (a raw binary; never base64).
    * `link` — the `ant://manifest/` link, or `nil` when it would not fit the
      recommended 1,500 bytes.
    * `entries` — `Antd.ManifestEntryInfo` structs in encoded order (sorted by
      effective name).
  """

  defstruct manifest: "", link: nil, entries: []

  @type t :: %__MODULE__{
          manifest: binary(),
          link: String.t() | nil,
          entries: [Antd.ManifestEntryInfo.t()]
        }
end

defmodule Antd.DecodedManifest do
  @moduledoc """
  The result of `decode_manifest` and `decode_manifest_link`.

    * `source` — `"manifest"`, or `"file_link"` for a file link or bare
      address (reported as one public entry with no path).
    * `name` — the suggested root directory name, or `nil`.
    * `torrent_info_hash_v1`, `torrent_info_hash_v2` — hex BitTorrent info
      hashes of the same files, each `nil` when absent.
    * `entries` — `Antd.ManifestEntryInfo` structs.
  """

  defstruct source: "",
            name: nil,
            torrent_info_hash_v1: nil,
            torrent_info_hash_v2: nil,
            entries: []

  @type t :: %__MODULE__{
          source: String.t(),
          name: String.t() | nil,
          torrent_info_hash_v1: String.t() | nil,
          torrent_info_hash_v2: String.t() | nil,
          entries: [Antd.ManifestEntryInfo.t()]
        }
end
