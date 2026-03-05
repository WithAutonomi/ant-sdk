from antd._proto.antd.v1 import common_pb2 as _common_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class GetGraphEntryRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class GetGraphEntryResponse(_message.Message):
    __slots__ = ("owner", "parents", "content", "descendants")
    OWNER_FIELD_NUMBER: _ClassVar[int]
    PARENTS_FIELD_NUMBER: _ClassVar[int]
    CONTENT_FIELD_NUMBER: _ClassVar[int]
    DESCENDANTS_FIELD_NUMBER: _ClassVar[int]
    owner: str
    parents: _containers.RepeatedScalarFieldContainer[str]
    content: str
    descendants: _containers.RepeatedCompositeFieldContainer[_common_pb2.GraphDescendant]
    def __init__(self, owner: _Optional[str] = ..., parents: _Optional[_Iterable[str]] = ..., content: _Optional[str] = ..., descendants: _Optional[_Iterable[_Union[_common_pb2.GraphDescendant, _Mapping]]] = ...) -> None: ...

class CheckGraphEntryRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class GraphExistsResponse(_message.Message):
    __slots__ = ("exists",)
    EXISTS_FIELD_NUMBER: _ClassVar[int]
    exists: bool
    def __init__(self, exists: bool = ...) -> None: ...

class PutGraphEntryRequest(_message.Message):
    __slots__ = ("owner_secret_key", "parents", "content", "descendants")
    OWNER_SECRET_KEY_FIELD_NUMBER: _ClassVar[int]
    PARENTS_FIELD_NUMBER: _ClassVar[int]
    CONTENT_FIELD_NUMBER: _ClassVar[int]
    DESCENDANTS_FIELD_NUMBER: _ClassVar[int]
    owner_secret_key: str
    parents: _containers.RepeatedScalarFieldContainer[str]
    content: str
    descendants: _containers.RepeatedCompositeFieldContainer[_common_pb2.GraphDescendant]
    def __init__(self, owner_secret_key: _Optional[str] = ..., parents: _Optional[_Iterable[str]] = ..., content: _Optional[str] = ..., descendants: _Optional[_Iterable[_Union[_common_pb2.GraphDescendant, _Mapping]]] = ...) -> None: ...

class PutGraphEntryResponse(_message.Message):
    __slots__ = ("cost", "address")
    COST_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    address: str
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ..., address: _Optional[str] = ...) -> None: ...

class GraphEntryCostRequest(_message.Message):
    __slots__ = ("public_key",)
    PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    public_key: str
    def __init__(self, public_key: _Optional[str] = ...) -> None: ...
