from antd._proto.antd.v1 import common_pb2 as _common_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class GetVaultRequest(_message.Message):
    __slots__ = ("secret_key",)
    SECRET_KEY_FIELD_NUMBER: _ClassVar[int]
    secret_key: str
    def __init__(self, secret_key: _Optional[str] = ...) -> None: ...

class GetVaultResponse(_message.Message):
    __slots__ = ("data", "content_type")
    DATA_FIELD_NUMBER: _ClassVar[int]
    CONTENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    content_type: int
    def __init__(self, data: _Optional[bytes] = ..., content_type: _Optional[int] = ...) -> None: ...

class PutVaultRequest(_message.Message):
    __slots__ = ("secret_key", "data", "content_type")
    SECRET_KEY_FIELD_NUMBER: _ClassVar[int]
    DATA_FIELD_NUMBER: _ClassVar[int]
    CONTENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    secret_key: str
    data: bytes
    content_type: int
    def __init__(self, secret_key: _Optional[str] = ..., data: _Optional[bytes] = ..., content_type: _Optional[int] = ...) -> None: ...

class PutVaultResponse(_message.Message):
    __slots__ = ("cost",)
    COST_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ...) -> None: ...

class VaultCostRequest(_message.Message):
    __slots__ = ("secret_key", "max_size")
    SECRET_KEY_FIELD_NUMBER: _ClassVar[int]
    MAX_SIZE_FIELD_NUMBER: _ClassVar[int]
    secret_key: str
    max_size: int
    def __init__(self, secret_key: _Optional[str] = ..., max_size: _Optional[int] = ...) -> None: ...
