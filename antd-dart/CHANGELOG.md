# Changelog

## Unreleased

- `PartialUploadError` (a `NetworkError` subclass) for a finalize that stored
  some chunks but not all: carries `chunksStored` / `chunksFailed` /
  `totalChunks`, `retryable` and `retentionKnown`. REST maps the daemon's 502
  `code: "PARTIAL_UPLOAD"` body (`retentionKnown` only when the body's
  `retryable` is a JSON boolean; daemons before 0.14.0 never send it). gRPC
  maps status `ABORTED` whose message starts with `Partial upload:`, parsing
  the counts from the message (`retentionKnown` only when all three counts
  parse, with the retained hint then deciding `retryable`; any other
  `ABORTED` stays a plain `AntdError`). `retryable`: call the same finalize
  with the same `upload_id` to store the remainder against the same payment.
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
