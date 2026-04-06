"""Dataclass models for antd SDK request/response types."""

from __future__ import annotations
from dataclasses import dataclass, field


@dataclass(frozen=True)
class HealthStatus:
    """Health check result from the antd daemon."""
    ok: bool
    network: str    # "default", "local", "alpha"


@dataclass(frozen=True)
class PutResult:
    """Result of a put/create operation."""
    cost: str       # atto tokens as string
    address: str    # hex


@dataclass(frozen=True)
class WalletAddress:
    """Wallet address from the antd daemon."""
    address: str    # hex, e.g. "0x..."


@dataclass(frozen=True)
class WalletBalance:
    """Wallet balance from the antd daemon."""
    balance: str        # atto tokens as string
    gas_balance: str    # atto gas tokens as string


@dataclass(frozen=True)
class PaymentInfo:
    """A single payment required for an upload."""
    quote_hash: str      # hex
    rewards_address: str # hex
    amount: str          # atto tokens as string


@dataclass(frozen=True)
class CandidateNodeEntry:
    """A candidate node within a merkle payment pool."""
    rewards_address: str = ""
    amount: str = ""


@dataclass(frozen=True)
class PoolCommitmentEntry:
    """A pool commitment containing candidate nodes for merkle batch payment."""
    pool_hash: str = ""
    candidates: list[CandidateNodeEntry] = field(default_factory=list)


@dataclass(frozen=True)
class PrepareUploadResult:
    """Result of preparing an upload for external signing."""
    upload_id: str                    # hex identifier
    payments: list[PaymentInfo] = field(default_factory=list)
    total_amount: str = ""
    data_payments_address: str = ""   # contract address
    payment_token_address: str = ""   # token contract address
    rpc_url: str = ""                 # EVM RPC URL
    payment_type: str = ""            # "wave_batch" or "merkle_batch"
    depth: int = 0                    # merkle tree depth
    pool_commitments: list[PoolCommitmentEntry] = field(default_factory=list)
    merkle_payment_timestamp: int = 0
    merkle_payments_address: str = "" # merkle payments contract address


@dataclass(frozen=True)
class FinalizeUploadResult:
    """Result of finalizing an externally-signed upload."""
    address: str         # hex address of stored data
    chunks_stored: int = 0
