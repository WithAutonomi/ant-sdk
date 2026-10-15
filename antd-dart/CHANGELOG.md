# Changelog

## Unreleased

- Manifests (ADR-0006 `.ant` files and `ant://` links), on both `AntdClient`
  and `GrpcAntdClient` (needs the antd release after 0.15.0):
  `buildManifest(entries, {name, torrentInfoHashes, embedRoots})`,
  `decodeManifest(bytes, {resolve})` and `decodeManifestLink(link,
  {resolve})`. Nothing is uploaded or paid for. New models
  `ManifestEntryInput` (exactly one of `dataMap` or `address`, checked before
  sending: an `ArgumentError` names `entries[i]`), `ManifestEntryInfo`,
  `BuiltManifest` and `DecodedManifest`. The `.ant` bytes are raw
  `Uint8List`s (base64 on the REST wire). `embedRoots` defaults to `true`.
  Sizes are `int?`, `null` when unset, never 0; over gRPC presence decides.
  Fields the daemon leaves unset (`link`, `name`, the torrent hashes, an
  entry's `path`, `dataMap` and `error`) are `null`. Invalid entries are the
  daemon's `BadRequestError` naming `entries[i]`; one entry's resolve
  failure is that entry's `error`, not a failed call.
- gRPC stubs regenerated with `manifests.proto`. `example/10_manifests.dart`.

## 0.2.0

- `PartialUploadError` (a `NetworkError` subclass) for a finalize that stored
  some chunks but not all: carries `chunksStored` / `chunksFailed` /
  `totalChunks`, `retryable` and `retentionKnown`. REST maps the daemon's 502
  `code: "PARTIAL_UPLOAD"` body (`retentionKnown` only when the body's
  `retryable` is a JSON boolean; daemons before 0.14.0 never send it). gRPC
  maps status `ABORTED` whose message starts with `Partial upload:`, parsing
  the counts from the message (`retentionKnown` only when all three counts
  parse and the message ends with one of the daemon's two retention hints:
  `(paid attempt retained...)` sets `retryable`, `(stored chunks persist;
  re-prepare the same content...)` means nothing was retained; readable
  counts with a missing, truncated or unrecognised hint keep the counts but
  read as retention unknown; any other `ABORTED` stays a plain `AntdError`).
  `retryable`: call the same finalize with the same `upload_id` to store the
  remainder against the same payment.
  `retentionKnown && !retryable`: nothing was retained, so re-prepare.
  `!retentionKnown`: retention is unknown, so keep the `upload_id` and
  payment artefacts and reconcile before re-preparing or paying again.
- `example/finalize_with_retry.dart` (used by `07_external_signer.dart`):
  `finalizeWithRetry`, a bounded retry loop around `finalizeUpload` that
  resumes only when `retryable`, stops at once when retention is unknown,
  stops when `chunksFailed` stops shrinking, and rethrows the
  `PartialUploadError` unchanged whenever it gives up.

## 0.1.0

Initial release on pub.dev as `antd_client`.

- REST client (`AntdClient`) and gRPC client (`GrpcAntdClient`) for the antd daemon.
- Public and private data put/get, raw chunk put/get, file upload/download.
- Cost estimation with payment-mode selection (`auto`, `merkle`, `single`).
- External-signer flow: prepare upload, pay with your own wallet, finalize.
- Typed error hierarchy (`AntdError` subclasses) shared by both transports.
- Tested against antd 0.13.x.
