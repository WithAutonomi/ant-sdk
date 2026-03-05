from antd._proto.antd.v1 import common_pb2 as _common_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class GetRegisterRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class GetRegisterResponse(_message.Message):
    __slots__ = ("value",)
    VALUE_FIELD_NUMBER: _ClassVar[int]
    value: str
    def __init__(self, value: _Optional[str] = ...) -> None: ...

class CreateRegisterRequest(_message.Message):
    __slots__ = ("owner_secret_key", "initial_value")
    OWNER_SECRET_KEY_FIELD_NUMBER: _ClassVar[int]
    INITIAL_VALUE_FIELD_NUMBER: _ClassVar[int]
    owner_secret_key: str
    initial_value: str
    def __init__(self, owner_secret_key: _Optional[str] = ..., initial_value: _Optional[str] = ...) -> None: ...

class CreateRegisterResponse(_message.Message):
    __slots__ = ("cost", "address")
    COST_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    address: str
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ..., address: _Optional[str] = ...) -> None: ...

class UpdateRegisterRequest(_message.Message):
    __slots__ = ("owner_secret_key", "new_value")
    OWNER_SECRET_KEY_FIELD_NUMBER: _ClassVar[int]
    NEW_VALUE_FIELD_NUMBER: _ClassVar[int]
    owner_secret_key: str
    new_value: str
    def __init__(self, owner_secret_key: _Optional[str] = ..., new_value: _Optional[str] = ...) -> None: ...

class UpdateRegisterResponse(_message.Message):
    __slots__ = ("cost",)
    COST_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ...) -> None: ...

class RegisterCostRequest(_message.Message):
    __slots__ = ("public_key",)
    PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    public_key: str
    def __init__(self, public_key: _Optional[str] = ...) -> None: ...
