"""Tests for the bounded finalize retry in examples/07_external_signer.py.

Running the example needs web3 / eth-account and a daemon, so these tests
load the module with those two imports stubbed (its script body sits under
``if __name__ == "__main__"``) and drive ``finalize_with_retry`` and
``next_step`` with a mock client.
"""

from __future__ import annotations

import importlib.util
import sys
import types
from pathlib import Path
from unittest.mock import Mock, call

import pytest

from antd import PartialUploadError
from antd.exceptions import parse_partial_upload_message

_EXAMPLE = Path(__file__).resolve().parents[1] / "examples" / "07_external_signer.py"
_TX = {"0xq1": "0xtx1"}


@pytest.fixture
def sleeps() -> list:
    return []


@pytest.fixture
def example(monkeypatch, sleeps):
    web3 = types.ModuleType("web3")
    web3.Web3 = object  # type: ignore[attr-defined]
    eth_account = types.ModuleType("eth_account")
    eth_account.Account = object  # type: ignore[attr-defined]
    monkeypatch.setitem(sys.modules, "web3", web3)
    monkeypatch.setitem(sys.modules, "eth_account", eth_account)
    spec = importlib.util.spec_from_file_location("example_07_external_signer", _EXAMPLE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # No real waiting between attempts; record the back-off instead.
    monkeypatch.setattr(module, "time", types.SimpleNamespace(sleep=sleeps.append))
    # The helper must never pay by itself; fail loudly if it tries.
    monkeypatch.setattr(module, "external_signer_pay", Mock(side_effect=AssertionError("paid")))
    return module


def _partial(*, failed: int, retryable: bool = False, retention_known: bool = False) -> PartialUploadError:
    total = 10
    return PartialUploadError(
        f"Partial upload: {total - failed}/{total} chunks stored, {failed} failed",
        502,
        chunks_stored=total - failed,
        chunks_failed=failed,
        total_chunks=total,
        retryable=retryable,
        retention_known=retention_known,
    )


def _client(*outcomes) -> Mock:
    client = Mock()
    client.finalize_upload.side_effect = list(outcomes)
    return client


def test_retryable_then_success_returns_the_result(example, sleeps):
    result = object()
    client = _client(_partial(failed=3, retryable=True), result)
    assert example.finalize_with_retry(client, "up-1", _TX) is result
    assert client.method_calls == [call.finalize_upload("up-1", _TX)] * 2
    assert sleeps == [2]


def test_attempts_exhausted_reraises_the_original_error(example):
    errors = [_partial(failed=n, retryable=True) for n in (5, 4, 3)]
    client = _client(*errors)
    with pytest.raises(PartialUploadError) as exc_info:
        example.finalize_with_retry(client, "up-1", _TX, max_attempts=3)
    assert exc_info.value is errors[-1]
    assert client.method_calls == [call.finalize_upload("up-1", _TX)] * 3


def test_stalled_progress_reraises_the_original_error(example):
    errors = [_partial(failed=4, retryable=True), _partial(failed=4, retryable=True)]
    client = _client(*errors)
    with pytest.raises(PartialUploadError) as exc_info:
        example.finalize_with_retry(client, "up-1", _TX)
    assert exc_info.value is errors[1]
    assert client.finalize_upload.call_count == 2


def test_known_not_retained_stops_at_once_with_the_original_error(example, sleeps):
    err = _partial(failed=4, retention_known=True)
    client = _client(err)
    with pytest.raises(PartialUploadError) as exc_info:
        example.finalize_with_retry(client, "up-1", _TX)
    assert exc_info.value is err
    assert client.method_calls == [call.finalize_upload("up-1", _TX)]
    assert sleeps == []


def test_unknown_retention_stops_without_repreparing_or_paying(example, sleeps):
    err = _partial(failed=4)  # retention_known False: e.g. antd < 0.14.0
    client = _client(err)
    with pytest.raises(PartialUploadError) as exc_info:
        example.finalize_with_retry(client, "up-1", _TX)
    assert exc_info.value is err
    # One finalize and nothing else: no prepare_*, no second finalize, no
    # payment, no back-off.
    assert client.method_calls == [call.finalize_upload("up-1", _TX)]
    example.external_signer_pay.assert_not_called()
    assert sleeps == []


@pytest.mark.parametrize(
    "flags, expected, unexpected",
    [
        ({"retryable": True}, "retry the same finalize later", "re-prepare"),
        ({"retention_known": True}, "re-prepare the same content", "retry the same finalize"),
        ({}, "Retention is unknown", "re-prepare the same content"),
    ],
    ids=["retryable", "known-not-retained", "unknown"],
)
def test_next_step_covers_the_three_cases(example, flags, expected, unexpected):
    advice = example.next_step(_partial(failed=4, **flags), "up-1")
    assert expected in advice
    assert unexpected not in advice


_GRPC_COUNTS = "Partial upload: 6/10 chunks stored, 4 failed after retries: quorum"


@pytest.mark.parametrize(
    "tail, expected, unexpected",
    [
        (
            " (stored chunks persist; re-prepare the same content to retry only the remainder)",
            "The daemon kept nothing",
            "Retention is unknown",
        ),
        ("", "Retention is unknown", "kept nothing"),
        # The review's reproducer: the retained hint cut short.
        (" (paid attempt retai", "Retention is unknown", "kept nothing"),
        (" (stored chunks persist; re-prepare the same con", "Retention is unknown", "kept nothing"),
    ],
    ids=["not-retained-hint", "no-hint", "truncated-retained-hint", "truncated-not-retained-hint"],
)
def test_grpc_message_without_a_readable_hint_gets_reconcile_advice(example, tail, expected, unexpected):
    # End to end from the gRPC status text: the SDK parser's flags must steer
    # next_step to reconciling, not re-preparing, whenever the daemon's
    # answer on retention could not be read.
    message = _GRPC_COUNTS + tail
    stored, failed, total, retryable, known = parse_partial_upload_message(message)
    err = PartialUploadError(
        message,
        10,
        chunks_stored=stored,
        chunks_failed=failed,
        total_chunks=total,
        retryable=retryable,
        retention_known=known,
    )
    advice = example.next_step(err, "up-1")
    assert expected in advice
    assert unexpected not in advice
    assert "6/10 chunks stored, 4 still unstored" in advice
