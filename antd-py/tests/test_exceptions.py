"""Unit tests for the PARTIAL_UPLOAD mapping in antd.exceptions: the REST
body-aware raiser and the gRPC message parser. Transport-level coverage lives
in test_rest_client.py / test_grpc_client.py."""

from __future__ import annotations

import pytest

from antd import PartialUploadError as ExportedPartialUploadError
from antd.exceptions import (
    AntdError,
    NetworkError,
    NotFoundError,
    PartialUploadError,
    parse_partial_upload_message,
    raise_for_http_error,
)

_RETAINED = (
    "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum "
    "(paid attempt retained: call finalize again with the same upload_id to "
    "store the remainder against the same payment)"
)
_REPREPARE = (
    "Partial upload: 300/312 chunks stored, 12 failed after retries: quorum "
    "(stored chunks persist; re-prepare the same content to retry only the remainder)"
)


class TestParsePartialUploadMessage:
    @pytest.mark.parametrize(
        "message, expected",
        [
            (_RETAINED, (300, 12, 312, True)),
            (_REPREPARE, (300, 12, 312, False)),
            ("Partial upload: 300/312 chunks stored, 12 failed after retries", (300, 12, 312, False)),
            ("something else entirely", (0, 0, 0, False)),
        ],
    )
    def test_table(self, message, expected):
        # (stored, failed, total, retryable)
        assert parse_partial_upload_message(message) == expected


class TestRaiseForHttpError:
    def test_partial_upload_body_with_flag(self):
        body = {
            "error": _RETAINED, "code": "PARTIAL_UPLOAD",
            "chunks_stored": 300, "chunks_failed": 12, "total_chunks": 312,
            "retryable": True,
        }
        with pytest.raises(PartialUploadError) as exc_info:
            raise_for_http_error(502, body["error"], body)
        err = exc_info.value
        assert err.status_code == 502
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (300, 12, 312)
        assert err.retryable is True

    def test_partial_upload_body_without_flag_defaults_false(self):
        # antd < 0.14.0 never sends `retryable`.
        body = {
            "error": _REPREPARE, "code": "PARTIAL_UPLOAD",
            "chunks_stored": 300, "chunks_failed": 12, "total_chunks": 312,
        }
        with pytest.raises(PartialUploadError) as exc_info:
            raise_for_http_error(502, body["error"], body)
        assert exc_info.value.retryable is False
        assert exc_info.value.chunks_failed == 12

    def test_other_codes_keep_status_mapping(self):
        with pytest.raises(NetworkError) as exc_info:
            raise_for_http_error(502, "upstream unreachable", {"error": "x", "code": "NETWORK_ERROR"})
        assert not isinstance(exc_info.value, PartialUploadError)
        with pytest.raises(NotFoundError):
            raise_for_http_error(404, "not found", {"error": "not found", "code": "NOT_FOUND"})

    def test_non_json_body_keeps_status_mapping(self):
        with pytest.raises(NetworkError) as exc_info:
            raise_for_http_error(502, "<html>bad gateway</html>", None)
        assert not isinstance(exc_info.value, PartialUploadError)

    def test_success_is_noop(self):
        raise_for_http_error(200, "", {"code": "PARTIAL_UPLOAD"})


class TestHierarchy:
    def test_subclasses_network_error_and_is_exported(self):
        err = PartialUploadError("m", 502, chunks_stored=1, chunks_failed=2, total_chunks=3, retryable=True)
        assert isinstance(err, NetworkError)
        assert isinstance(err, AntdError)
        assert ExportedPartialUploadError is PartialUploadError
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks, err.retryable) == (1, 2, 3, True)

    def test_defaults(self):
        err = PartialUploadError("m")
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks, err.retryable) == (0, 0, 0, False)
