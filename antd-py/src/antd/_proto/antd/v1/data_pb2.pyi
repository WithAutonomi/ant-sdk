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
    __slots__ = ("cost", "address", "chunks_stored", "payment_mode_used")
    COST_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    CHUNKS_STORED_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_MODE_USED_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    address: str
    chunks_stored: int
    payment_mode_used: str
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ..., address: _Optional[str] = ..., chunks_stored: _Optional[int] = ..., payment_mode_used: _Optional[str] = ...) -> None: ...

class StreamPublicDataRequest(_message.Message):
    __slots__ = ("address", "include_progress")
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_PROGRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    include_progress: bool
    def __init__(self, address: _Optional[str] = ..., include_progress: bool = ...) -> None: ...

class DataChunk(_message.Message):
    __slots__ = ("data", "progress")
    DATA_FIELD_NUMBER: _ClassVar[int]
    PROGRESS_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    progress: DownloadProgress
    def __init__(self, data: _Optional[bytes] = ..., progress: _Optional[_Union[DownloadProgress, _Mapping]] = ...) -> None: ...

class DownloadProgress(_message.Message):
    __slots__ = ("phase", "fetched", "total")
    PHASE_FIELD_NUMBER: _ClassVar[int]
    FETCHED_FIELD_NUMBER: _ClassVar[int]
    TOTAL_FIELD_NUMBER: _ClassVar[int]
    phase: str
    fetched: int
    total: int
    def __init__(self, phase: _Optional[str] = ..., fetched: _Optional[int] = ..., total: _Optional[int] = ...) -> None: ...

class GetDataRequest(_message.Message):
    __slots__ = ("data_map",)
    DATA_MAP_FIELD_NUMBER: _ClassVar[int]
    data_map: str
    def __init__(self, data_map: _Optional[str] = ...) -> None: ...

class StreamDataRequest(_message.Message):
    __slots__ = ("data_map", "include_progress")
    DATA_MAP_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_PROGRESS_FIELD_NUMBER: _ClassVar[int]
    data_map: str
    include_progress: bool
    def __init__(self, data_map: _Optional[str] = ..., include_progress: bool = ...) -> None: ...

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
    __slots__ = ("cost", "data_map", "chunks_stored", "payment_mode_used")
    COST_FIELD_NUMBER: _ClassVar[int]
    DATA_MAP_FIELD_NUMBER: _ClassVar[int]
    CHUNKS_STORED_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_MODE_USED_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    data_map: str
    chunks_stored: int
    payment_mode_used: str
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ..., data_map: _Optional[str] = ..., chunks_stored: _Optional[int] = ..., payment_mode_used: _Optional[str] = ...) -> None: ...

class DataCostRequest(_message.Message):
    __slots__ = ("data", "payment_mode")
    DATA_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_MODE_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    payment_mode: str
    def __init__(self, data: _Optional[bytes] = ..., payment_mode: _Optional[str] = ...) -> None: ...
