from antd._proto.antd.v1 import common_pb2 as _common_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class UploadFileRequest(_message.Message):
    __slots__ = ("path",)
    PATH_FIELD_NUMBER: _ClassVar[int]
    path: str
    def __init__(self, path: _Optional[str] = ...) -> None: ...

class UploadPublicResponse(_message.Message):
    __slots__ = ("address", "storage_cost_atto", "gas_cost_wei", "chunks_stored", "payment_mode_used")
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    STORAGE_COST_ATTO_FIELD_NUMBER: _ClassVar[int]
    GAS_COST_WEI_FIELD_NUMBER: _ClassVar[int]
    CHUNKS_STORED_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_MODE_USED_FIELD_NUMBER: _ClassVar[int]
    address: str
    storage_cost_atto: str
    gas_cost_wei: str
    chunks_stored: int
    payment_mode_used: str
    def __init__(self, address: _Optional[str] = ..., storage_cost_atto: _Optional[str] = ..., gas_cost_wei: _Optional[str] = ..., chunks_stored: _Optional[int] = ..., payment_mode_used: _Optional[str] = ...) -> None: ...

class DownloadPublicRequest(_message.Message):
    __slots__ = ("address", "dest_path")
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    DEST_PATH_FIELD_NUMBER: _ClassVar[int]
    address: str
    dest_path: str
    def __init__(self, address: _Optional[str] = ..., dest_path: _Optional[str] = ...) -> None: ...

class DownloadResponse(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...

class FileCostRequest(_message.Message):
    __slots__ = ("path", "is_public")
    PATH_FIELD_NUMBER: _ClassVar[int]
    IS_PUBLIC_FIELD_NUMBER: _ClassVar[int]
    path: str
    is_public: bool
    def __init__(self, path: _Optional[str] = ..., is_public: bool = ...) -> None: ...
