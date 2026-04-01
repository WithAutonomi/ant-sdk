from antd.v1 import common_pb2 as _common_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class UploadFileRequest(_message.Message):
    __slots__ = ("path",)
    PATH_FIELD_NUMBER: _ClassVar[int]
    path: str
    def __init__(self, path: _Optional[str] = ...) -> None: ...

class UploadPublicResponse(_message.Message):
    __slots__ = ("cost", "address")
    COST_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    address: str
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ..., address: _Optional[str] = ...) -> None: ...

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
