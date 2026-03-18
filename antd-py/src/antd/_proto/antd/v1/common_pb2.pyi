from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class Cost(_message.Message):
    __slots__ = ("atto_tokens",)
    ATTO_TOKENS_FIELD_NUMBER: _ClassVar[int]
    atto_tokens: str
    def __init__(self, atto_tokens: _Optional[str] = ...) -> None: ...

class Address(_message.Message):
    __slots__ = ("hex",)
    HEX_FIELD_NUMBER: _ClassVar[int]
    hex: str
    def __init__(self, hex: _Optional[str] = ...) -> None: ...

class PublicKeyProto(_message.Message):
    __slots__ = ("hex",)
    HEX_FIELD_NUMBER: _ClassVar[int]
    hex: str
    def __init__(self, hex: _Optional[str] = ...) -> None: ...

class SecretKeyProto(_message.Message):
    __slots__ = ("hex",)
    HEX_FIELD_NUMBER: _ClassVar[int]
    hex: str
    def __init__(self, hex: _Optional[str] = ...) -> None: ...

class GraphDescendant(_message.Message):
    __slots__ = ("public_key", "content")
    PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    CONTENT_FIELD_NUMBER: _ClassVar[int]
    public_key: str
    content: str
    def __init__(self, public_key: _Optional[str] = ..., content: _Optional[str] = ...) -> None: ...
