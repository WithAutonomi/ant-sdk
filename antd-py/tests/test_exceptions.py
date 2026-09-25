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
    is_partial_upload_message,
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


# ---------------------------------------------------------------------------
# Malformed input. Nothing escapes as a raw ValueError / TypeError /
# OverflowError, a malformed count reads as 0, and only an unambiguous daemon
# signal reads as retryable.
# ---------------------------------------------------------------------------

_U64_MAX = 18446744073709551615

_HINT = (
    "(paid attempt retained: call finalize again with the same upload_id to "
    "store the remainder against the same payment)"
)

_WELL_FORMED_BODY = {
    "error": _RETAINED, "code": "PARTIAL_UPLOAD",
    "chunks_stored": 300, "chunks_failed": 12, "total_chunks": 312,
    "retryable": True,
}

_COUNT_FIELDS = ("chunks_stored", "chunks_failed", "total_chunks")

# Every value is one json.loads can produce. Python's json also accepts the
# Infinity / -Infinity / NaN literals, which is where the floats come from.
_MALFORMED_COUNTS = [
    "1", "abc", "1.5", True, False, 1.5, 1.0, -1, [], [1], {}, None,
    _U64_MAX + 1, float("inf"), float("-inf"), float("nan"),
]


def _raise_partial(body) -> PartialUploadError:
    with pytest.raises(PartialUploadError) as exc_info:
        raise_for_http_error(502, "m", body)
    return exc_info.value


class TestRaiseForHttpErrorMalformedBody:
    @pytest.mark.parametrize("field", _COUNT_FIELDS)
    @pytest.mark.parametrize("value", _MALFORMED_COUNTS, ids=repr)
    def test_malformed_count_reads_zero(self, field, value):
        err = _raise_partial({**_WELL_FORMED_BODY, field: value})
        got = {f: getattr(err, f) for f in _COUNT_FIELDS}
        expected = {f: 0 if f == field else _WELL_FORMED_BODY[f] for f in _COUNT_FIELDS}
        assert got == expected
        # Over REST the daemon's own `retryable` field is authoritative, so a
        # bad count leaves it (and the other counts) alone.
        assert err.retryable is True

    @pytest.mark.parametrize("value", [0, 1, _U64_MAX])
    def test_count_range_is_inclusive(self, value):
        err = _raise_partial({**_WELL_FORMED_BODY, "chunks_failed": value})
        assert err.chunks_failed == value
        assert type(err.chunks_failed) is int

    @pytest.mark.parametrize(
        "value", ["true", "True", "false", 1, 0, 1.0, {}, [], [True], None, False], ids=repr,
    )
    def test_retryable_only_for_json_true(self, value):
        err = _raise_partial({**_WELL_FORMED_BODY, "retryable": value})
        assert err.retryable is False
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks) == (300, 12, 312)

    @pytest.mark.parametrize(
        "code",
        [{}, [], None, 1, True, "partial_upload", "PARTIAL_UPLOAD ", ["PARTIAL_UPLOAD"]],
        ids=repr,
    )
    def test_code_must_be_the_exact_string(self, code):
        with pytest.raises(NetworkError) as exc_info:
            raise_for_http_error(502, "m", {**_WELL_FORMED_BODY, "code": code})
        assert type(exc_info.value) is NetworkError
        assert exc_info.value.status_code == 502

    def test_missing_code_keeps_status_mapping(self):
        body = {k: v for k, v in _WELL_FORMED_BODY.items() if k != "code"}
        with pytest.raises(NetworkError) as exc_info:
            raise_for_http_error(502, "m", body)
        assert type(exc_info.value) is NetworkError

    @pytest.mark.parametrize(
        "body", [[], [_WELL_FORMED_BODY], "PARTIAL_UPLOAD", 502, 1.5, True, None], ids=repr,
    )
    def test_non_object_body_keeps_status_mapping(self, body):
        with pytest.raises(NetworkError) as exc_info:
            raise_for_http_error(502, "m", body)
        assert type(exc_info.value) is NetworkError
        assert str(exc_info.value) == "m"

    def test_everything_malformed_at_once(self):
        err = _raise_partial({
            "error": {}, "code": "PARTIAL_UPLOAD",
            "chunks_stored": "300", "chunks_failed": float("inf"), "total_chunks": [312],
            "retryable": "true",
        })
        assert (err.chunks_stored, err.chunks_failed, err.total_chunks, err.retryable) == (0, 0, 0, False)


class TestIsPartialUploadMessage:
    @pytest.mark.parametrize(
        "details, expected",
        [
            ("Partial upload: 1/3 chunks stored, 2 failed", True),
            ("Partial upload: counts unavailable", True),
            # Anchored: an embedded marker is some other failure.
            ("upstream error: Partial upload: 1/3 chunks stored, 2 failed", False),
            (" Partial upload: 1/3 chunks stored, 2 failed", False),
            ("partial upload: 1/3 chunks stored, 2 failed", False),
            ("version conflict: upload was superseded", False),
            ("", False),
            (None, False),
        ],
    )
    def test_table(self, details, expected):
        assert is_partial_upload_message(details) is expected


# u64::MAX + 1, a 25-digit value, and one past int()'s 4300-digit limit
# (Python >= 3.11 raises ValueError converting it).
_UNCONVERTIBLE_COUNTS = [str(_U64_MAX + 1), "9" * 25, "9" * 5000]


class TestParsePartialUploadMessageMalformed:
    """The counts gate the retry: retryable only when the pattern matched,
    all three counts converted, and the hint is present."""

    @pytest.mark.parametrize("position", ["stored", "total", "failed"])
    @pytest.mark.parametrize("value", _UNCONVERTIBLE_COUNTS, ids=lambda v: f"{len(v)}-digits")
    def test_unconvertible_count_zeroes_all_and_blocks_retry(self, position, value):
        counts = {"stored": "1", "total": "3", "failed": "2"}
        counts[position] = value
        message = (
            f"Partial upload: {counts['stored']}/{counts['total']} chunks stored, "
            f"{counts['failed']} failed after retries: quorum {_HINT}"
        )
        assert parse_partial_upload_message(message) == (0, 0, 0, False)

    def test_u64_max_counts_convert(self):
        message = f"Partial upload: {_U64_MAX}/{_U64_MAX} chunks stored, {_U64_MAX} failed {_HINT}"
        assert parse_partial_upload_message(message) == (_U64_MAX, _U64_MAX, _U64_MAX, True)

    @pytest.mark.parametrize(
        "message",
        [
            f"Partial upload: counts unavailable {_HINT}",
            f"Partial upload: -1/3 chunks stored, 2 failed {_HINT}",
            f"Partial upload: 1.5/3 chunks stored, 2 failed {_HINT}",
            f"Partial upload: 1/3 chunks stored {_HINT}",
            f"Partial upload:1/3 chunks stored, 2 failed {_HINT}",
            # Arabic-Indic digits: int() would accept them, the ASCII-only
            # pattern does not.
            f"Partial upload: \u0661/\u0663 chunks stored, \u0662 failed {_HINT}",
            _HINT,
        ],
    )
    def test_pattern_miss_with_hint_is_not_retryable(self, message):
        assert parse_partial_upload_message(message) == (0, 0, 0, False)

    def test_well_formed_with_hint_is_retryable(self):
        message = f"Partial upload: 1/3 chunks stored, 2 failed after retries: quorum {_HINT}"
        assert parse_partial_upload_message(message) == (1, 2, 3, True)

    def test_well_formed_without_hint_is_not_retryable(self):
        message = "Partial upload: 1/3 chunks stored, 2 failed after retries: quorum"
        assert parse_partial_upload_message(message) == (1, 2, 3, False)

    def test_non_string_reads_zero(self):
        assert parse_partial_upload_message(None) == (0, 0, 0, False)  # type: ignore[arg-type]
