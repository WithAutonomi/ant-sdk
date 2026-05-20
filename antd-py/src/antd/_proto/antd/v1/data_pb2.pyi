from antd._proto.antd.v1 import common_pb2 as _common_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class GetPublicDataRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class GetPublicDataResponse(_message.Message):
    __slots__ = ("data",)
    DATA_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    def __init__(self, data: _Optional[bytes] = ...) -> None: ...

class PutPublicDataRequest(_message.Message):
    __slots__ = ("data", "payment_mode")
    DATA_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_MODE_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    payment_mode: str
    def __init__(self, data: _Optional[bytes] = ..., payment_mode: _Optional[str] = ...) -> None: ...

class PutPublicDataResponse(_message.Message):
    __slots__ = ("cost", "address")
    COST_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    address: str
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ..., address: _Optional[str] = ...) -> None: ...

class StreamPublicDataRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class DataChunk(_message.Message):
    __slots__ = ("data",)
    DATA_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    def __init__(self, data: _Optional[bytes] = ...) -> None: ...

class GetDataRequest(_message.Message):
    __slots__ = ("data_map",)
    DATA_MAP_FIELD_NUMBER: _ClassVar[int]
    data_map: str
    def __init__(self, data_map: _Optional[str] = ...) -> None: ...

class GetDataResponse(_message.Message):
    __slots__ = ("data",)
    DATA_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    def __init__(self, data: _Optional[bytes] = ...) -> None: ...

class PutDataRequest(_message.Message):
    __slots__ = ("data", "payment_mode")
    DATA_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_MODE_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    payment_mode: str
    def __init__(self, data: _Optional[bytes] = ..., payment_mode: _Optional[str] = ...) -> None: ...

class PutDataResponse(_message.Message):
    __slots__ = ("cost", "data_map")
    COST_FIELD_NUMBER: _ClassVar[int]
    DATA_MAP_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    data_map: str
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ..., data_map: _Optional[str] = ...) -> None: ...

class DataCostRequest(_message.Message):
    __slots__ = ("data", "payment_mode")
    DATA_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_MODE_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    payment_mode: str
    def __init__(self, data: _Optional[bytes] = ..., payment_mode: _Optional[str] = ...) -> None: ...
