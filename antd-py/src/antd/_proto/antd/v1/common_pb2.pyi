from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class Cost(_message.Message):
    __slots__ = ("atto_tokens", "file_size", "chunk_count", "estimated_gas_cost_wei", "payment_mode")
    ATTO_TOKENS_FIELD_NUMBER: _ClassVar[int]
    FILE_SIZE_FIELD_NUMBER: _ClassVar[int]
    CHUNK_COUNT_FIELD_NUMBER: _ClassVar[int]
    ESTIMATED_GAS_COST_WEI_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_MODE_FIELD_NUMBER: _ClassVar[int]
    atto_tokens: str
    file_size: int
    chunk_count: int
    estimated_gas_cost_wei: str
    payment_mode: str
    def __init__(self, atto_tokens: _Optional[str] = ..., file_size: _Optional[int] = ..., chunk_count: _Optional[int] = ..., estimated_gas_cost_wei: _Optional[str] = ..., payment_mode: _Optional[str] = ...) -> None: ...

class Address(_message.Message):
    __slots__ = ("hex",)
    HEX_FIELD_NUMBER: _ClassVar[int]
    hex: str
    def __init__(self, hex: _Optional[str] = ...) -> None: ...

class PublicKeyProto(_message.Message):
    __slots__ = ("hex",)
    HEX_FIELD_NUMBER: _ClassVar[int]
    hex: str
    def __init__(self, hex: _Optional[str] = ...) -> None: ...

class SecretKeyProto(_message.Message):
    __slots__ = ("hex",)
    HEX_FIELD_NUMBER: _ClassVar[int]
    hex: str
    def __init__(self, hex: _Optional[str] = ...) -> None: ...
