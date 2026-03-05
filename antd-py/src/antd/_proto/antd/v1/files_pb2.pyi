from antd._proto.antd.v1 import common_pb2 as _common_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
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

class ArchiveGetRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class ArchiveEntry(_message.Message):
    __slots__ = ("path", "address", "created", "modified", "size")
    PATH_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    CREATED_FIELD_NUMBER: _ClassVar[int]
    MODIFIED_FIELD_NUMBER: _ClassVar[int]
    SIZE_FIELD_NUMBER: _ClassVar[int]
    path: str
    address: str
    created: int
    modified: int
    size: int
    def __init__(self, path: _Optional[str] = ..., address: _Optional[str] = ..., created: _Optional[int] = ..., modified: _Optional[int] = ..., size: _Optional[int] = ...) -> None: ...

class ArchiveGetResponse(_message.Message):
    __slots__ = ("entries",)
    ENTRIES_FIELD_NUMBER: _ClassVar[int]
    entries: _containers.RepeatedCompositeFieldContainer[ArchiveEntry]
    def __init__(self, entries: _Optional[_Iterable[_Union[ArchiveEntry, _Mapping]]] = ...) -> None: ...

class ArchivePutRequest(_message.Message):
    __slots__ = ("entries",)
    ENTRIES_FIELD_NUMBER: _ClassVar[int]
    entries: _containers.RepeatedCompositeFieldContainer[ArchiveEntry]
    def __init__(self, entries: _Optional[_Iterable[_Union[ArchiveEntry, _Mapping]]] = ...) -> None: ...

class ArchivePutResponse(_message.Message):
    __slots__ = ("cost", "address")
    COST_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    address: str
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ..., address: _Optional[str] = ...) -> None: ...

class FileCostRequest(_message.Message):
    __slots__ = ("path", "is_public", "include_archive")
    PATH_FIELD_NUMBER: _ClassVar[int]
    IS_PUBLIC_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_ARCHIVE_FIELD_NUMBER: _ClassVar[int]
    path: str
    is_public: bool
    include_archive: bool
    def __init__(self, path: _Optional[str] = ..., is_public: bool = ..., include_archive: bool = ...) -> None: ...
