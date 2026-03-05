from antd._proto.antd.v1 import common_pb2 as _common_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class GetScratchpadRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class GetScratchpadResponse(_message.Message):
    __slots__ = ("address", "data_encoding", "data", "counter")
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    DATA_ENCODING_FIELD_NUMBER: _ClassVar[int]
    DATA_FIELD_NUMBER: _ClassVar[int]
    COUNTER_FIELD_NUMBER: _ClassVar[int]
    address: str
    data_encoding: int
    data: bytes
    counter: int
    def __init__(self, address: _Optional[str] = ..., data_encoding: _Optional[int] = ..., data: _Optional[bytes] = ..., counter: _Optional[int] = ...) -> None: ...

class CheckScratchpadRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class ScratchpadExistsResponse(_message.Message):
    __slots__ = ("exists",)
    EXISTS_FIELD_NUMBER: _ClassVar[int]
    exists: bool
    def __init__(self, exists: bool = ...) -> None: ...

class CreateScratchpadRequest(_message.Message):
    __slots__ = ("owner_secret_key", "content_type", "data")
    OWNER_SECRET_KEY_FIELD_NUMBER: _ClassVar[int]
    CONTENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    DATA_FIELD_NUMBER: _ClassVar[int]
    owner_secret_key: str
    content_type: int
    data: bytes
    def __init__(self, owner_secret_key: _Optional[str] = ..., content_type: _Optional[int] = ..., data: _Optional[bytes] = ...) -> None: ...

class CreateScratchpadResponse(_message.Message):
    __slots__ = ("cost", "address")
    COST_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    address: str
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ..., address: _Optional[str] = ...) -> None: ...

class UpdateScratchpadRequest(_message.Message):
    __slots__ = ("owner_secret_key", "content_type", "data")
    OWNER_SECRET_KEY_FIELD_NUMBER: _ClassVar[int]
    CONTENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    DATA_FIELD_NUMBER: _ClassVar[int]
    owner_secret_key: str
    content_type: int
    data: bytes
    def __init__(self, owner_secret_key: _Optional[str] = ..., content_type: _Optional[int] = ..., data: _Optional[bytes] = ...) -> None: ...

class UpdateScratchpadResponse(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...

class ScratchpadCostRequest(_message.Message):
    __slots__ = ("public_key",)
    PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    public_key: str
    def __init__(self, public_key: _Optional[str] = ...) -> None: ...
