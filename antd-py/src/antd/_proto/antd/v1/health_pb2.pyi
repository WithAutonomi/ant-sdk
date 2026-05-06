from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class HealthCheckRequest(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...

class HealthCheckResponse(_message.Message):
    __slots__ = ("status", "network", "version", "evm_network", "uptime_seconds", "build_commit", "payment_token_address", "payment_vault_address")
    STATUS_FIELD_NUMBER: _ClassVar[int]
    NETWORK_FIELD_NUMBER: _ClassVar[int]
    VERSION_FIELD_NUMBER: _ClassVar[int]
    EVM_NETWORK_FIELD_NUMBER: _ClassVar[int]
    UPTIME_SECONDS_FIELD_NUMBER: _ClassVar[int]
    BUILD_COMMIT_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_TOKEN_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_VAULT_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    status: str
    network: str
    version: str
    evm_network: str
    uptime_seconds: int
    build_commit: str
    payment_token_address: str
    payment_vault_address: str
    def __init__(self, status: _Optional[str] = ..., network: _Optional[str] = ..., version: _Optional[str] = ..., evm_network: _Optional[str] = ..., uptime_seconds: _Optional[int] = ..., build_commit: _Optional[str] = ..., payment_token_address: _Optional[str] = ..., payment_vault_address: _Optional[str] = ...) -> None: ...
