# Changelog

## Unreleased

- `PartialUploadError` (a `NetworkError` subclass) for a finalize that stored
  some chunks but not all: carries `chunksStored` / `chunksFailed` /
  `totalChunks` and `retryable`. REST maps the daemon's 502
  `code: "PARTIAL_UPLOAD"` body; gRPC maps status `ABORTED` whose message
  starts with `Partial upload:`, parsing the counts from the message
  (`retryable` only when all three counts parse and the retained hint is
  present; any other `ABORTED` stays a plain `AntdError`). `retryable == true`
  (antd ≥ 0.14.0) means the same finalize call with the same `upload_id`
  stores the remainder against the
  same payment; older daemons never send the flag, so it reads `false`.
- `example/finalize_with_retry.dart` (used by `07_external_signer.dart`):
  `finalizeWithRetry`, a bounded retry loop around `finalizeUpload` that
  resumes only when `retryable`, stops when `chunksFailed` stops shrinking,
  and then rethrows the last `PartialUploadError` unchanged.

## 0.1.0

Initial release on pub.dev as `antd_client`.

- REST client (`AntdClient`) and gRPC client (`GrpcAntdClient`) for the antd daemon.
- Public and private data put/get, raw chunk put/get, file upload/download.
- Cost estimation with payment-mode selection (`auto`, `merkle`, `single`).
- External-signer flow: prepare upload, pay with your own wallet, finalize.
- Typed error hierarchy (`AntdError` subclasses) shared by both transports.
- Tested against antd 0.13.x.
