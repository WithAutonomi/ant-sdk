from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class ManifestEntryInput(_message.Message):
    __slots__ = ("path", "size", "sha256", "data_map", "address")
    PATH_FIELD_NUMBER: _ClassVar[int]
    SIZE_FIELD_NUMBER: _ClassVar[int]
    SHA256_FIELD_NUMBER: _ClassVar[int]
    DATA_MAP_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    path: str
    size: int
    sha256: str
    data_map: str
    address: str
    def __init__(self, path: _Optional[str] = ..., size: _Optional[int] = ..., sha256: _Optional[str] = ..., data_map: _Optional[str] = ..., address: _Optional[str] = ...) -> None: ...

class BuildManifestRequest(_message.Message):
    __slots__ = ("name", "torrent_info_hashes", "embed_roots", "entries")
    NAME_FIELD_NUMBER: _ClassVar[int]
    TORRENT_INFO_HASHES_FIELD_NUMBER: _ClassVar[int]
    EMBED_ROOTS_FIELD_NUMBER: _ClassVar[int]
    ENTRIES_FIELD_NUMBER: _ClassVar[int]
    name: str
    torrent_info_hashes: _containers.RepeatedScalarFieldContainer[str]
    embed_roots: bool
    entries: _containers.RepeatedCompositeFieldContainer[ManifestEntryInput]
    def __init__(self, name: _Optional[str] = ..., torrent_info_hashes: _Optional[_Iterable[str]] = ..., embed_roots: bool = ..., entries: _Optional[_Iterable[_Union[ManifestEntryInput, _Mapping]]] = ...) -> None: ...

class ManifestEntryInfo(_message.Message):
    __slots__ = ("effective_name", "path", "size", "kind", "content_address", "data_map", "exact_size", "error", "sha256")
    EFFECTIVE_NAME_FIELD_NUMBER: _ClassVar[int]
    PATH_FIELD_NUMBER: _ClassVar[int]
    SIZE_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    CONTENT_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    DATA_MAP_FIELD_NUMBER: _ClassVar[int]
    EXACT_SIZE_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    SHA256_FIELD_NUMBER: _ClassVar[int]
    effective_name: str
    path: str
    size: int
    kind: str
    content_address: str
    data_map: str
    exact_size: int
    error: str
    sha256: str
    def __init__(self, effective_name: _Optional[str] = ..., path: _Optional[str] = ..., size: _Optional[int] = ..., kind: _Optional[str] = ..., content_address: _Optional[str] = ..., data_map: _Optional[str] = ..., exact_size: _Optional[int] = ..., error: _Optional[str] = ..., sha256: _Optional[str] = ...) -> None: ...

class BuildManifestResponse(_message.Message):
    __slots__ = ("manifest", "link", "entries")
    MANIFEST_FIELD_NUMBER: _ClassVar[int]
    LINK_FIELD_NUMBER: _ClassVar[int]
    ENTRIES_FIELD_NUMBER: _ClassVar[int]
    manifest: bytes
    link: str
    entries: _containers.RepeatedCompositeFieldContainer[ManifestEntryInfo]
    def __init__(self, manifest: _Optional[bytes] = ..., link: _Optional[str] = ..., entries: _Optional[_Iterable[_Union[ManifestEntryInfo, _Mapping]]] = ...) -> None: ...

class DecodeManifestRequest(_message.Message):
    __slots__ = ("manifest", "link", "resolve")
    MANIFEST_FIELD_NUMBER: _ClassVar[int]
    LINK_FIELD_NUMBER: _ClassVar[int]
    RESOLVE_FIELD_NUMBER: _ClassVar[int]
    manifest: bytes
    link: str
    resolve: bool
    def __init__(self, manifest: _Optional[bytes] = ..., link: _Optional[str] = ..., resolve: bool = ...) -> None: ...

class DecodeManifestResponse(_message.Message):
    __slots__ = ("source", "name", "torrent_info_hash_v1", "torrent_info_hash_v2", "entries")
    SOURCE_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    TORRENT_INFO_HASH_V1_FIELD_NUMBER: _ClassVar[int]
    TORRENT_INFO_HASH_V2_FIELD_NUMBER: _ClassVar[int]
    ENTRIES_FIELD_NUMBER: _ClassVar[int]
    source: str
    name: str
    torrent_info_hash_v1: str
    torrent_info_hash_v2: str
    entries: _containers.RepeatedCompositeFieldContainer[ManifestEntryInfo]
    def __init__(self, source: _Optional[str] = ..., name: _Optional[str] = ..., torrent_info_hash_v1: _Optional[str] = ..., torrent_info_hash_v2: _Optional[str] = ..., entries: _Optional[_Iterable[_Union[ManifestEntryInfo, _Mapping]]] = ...) -> None: ...
