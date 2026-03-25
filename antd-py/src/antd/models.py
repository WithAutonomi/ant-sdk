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
class GraphDescendant:
    """A descendant entry in a graph node."""
    public_key: str     # hex
    content: str        # hex, 32 bytes


@dataclass(frozen=True)
class GraphEntry:
    """A graph entry from the network."""
    owner: str
    parents: list[str] = field(default_factory=list)
    content: str = ""
    descendants: list[GraphDescendant] = field(default_factory=list)


@dataclass(frozen=True)
class ArchiveEntry:
    """An entry in a file archive."""
    path: str
    address: str
    created: int
    modified: int
    size: int


@dataclass(frozen=True)
class Archive:
    """A collection of archive entries."""
    entries: list[ArchiveEntry] = field(default_factory=list)


@dataclass(frozen=True)
class WalletAddress:
    """Wallet address from the antd daemon."""
    address: str    # hex, e.g. "0x..."


@dataclass(frozen=True)
class WalletBalance:
    """Wallet balance from the antd daemon."""
    balance: str        # atto tokens as string
    gas_balance: str    # atto gas tokens as string
