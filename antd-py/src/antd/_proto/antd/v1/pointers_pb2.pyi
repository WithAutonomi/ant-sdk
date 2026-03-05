from antd._proto.antd.v1 import common_pb2 as _common_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class GetPointerRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class GetPointerResponse(_message.Message):
    __slots__ = ("address", "owner", "counter", "target")
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    OWNER_FIELD_NUMBER: _ClassVar[int]
    COUNTER_FIELD_NUMBER: _ClassVar[int]
    TARGET_FIELD_NUMBER: _ClassVar[int]
    address: str
    owner: str
    counter: int
    target: _common_pb2.PointerTarget
    def __init__(self, address: _Optional[str] = ..., owner: _Optional[str] = ..., counter: _Optional[int] = ..., target: _Optional[_Union[_common_pb2.PointerTarget, _Mapping]] = ...) -> None: ...

class CheckPointerRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class ExistsResponse(_message.Message):
    __slots__ = ("exists",)
    EXISTS_FIELD_NUMBER: _ClassVar[int]
    exists: bool
    def __init__(self, exists: bool = ...) -> None: ...

class CreatePointerRequest(_message.Message):
    __slots__ = ("owner_secret_key", "target")
    OWNER_SECRET_KEY_FIELD_NUMBER: _ClassVar[int]
    TARGET_FIELD_NUMBER: _ClassVar[int]
    owner_secret_key: str
    target: _common_pb2.PointerTarget
    def __init__(self, owner_secret_key: _Optional[str] = ..., target: _Optional[_Union[_common_pb2.PointerTarget, _Mapping]] = ...) -> None: ...

class CreatePointerResponse(_message.Message):
    __slots__ = ("cost", "address")
    COST_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    address: str
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ..., address: _Optional[str] = ...) -> None: ...

class UpdatePointerRequest(_message.Message):
    __slots__ = ("owner_secret_key", "target")
    OWNER_SECRET_KEY_FIELD_NUMBER: _ClassVar[int]
    TARGET_FIELD_NUMBER: _ClassVar[int]
    owner_secret_key: str
    target: _common_pb2.PointerTarget
    def __init__(self, owner_secret_key: _Optional[str] = ..., target: _Optional[_Union[_common_pb2.PointerTarget, _Mapping]] = ...) -> None: ...

class UpdatePointerResponse(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...

class PointerCostRequest(_message.Message):
    __slots__ = ("public_key",)
    PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    public_key: str
    def __init__(self, public_key: _Optional[str] = ...) -> None: ...
