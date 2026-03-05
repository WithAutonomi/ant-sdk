from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class SubscribeRequest(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...

class ClientEventProto(_message.Message):
    __slots__ = ("kind", "records_paid", "records_already_paid", "tokens_spent")
    KIND_FIELD_NUMBER: _ClassVar[int]
    RECORDS_PAID_FIELD_NUMBER: _ClassVar[int]
    RECORDS_ALREADY_PAID_FIELD_NUMBER: _ClassVar[int]
    TOKENS_SPENT_FIELD_NUMBER: _ClassVar[int]
    kind: str
    records_paid: int
    records_already_paid: int
    tokens_spent: str
    def __init__(self, kind: _Optional[str] = ..., records_paid: _Optional[int] = ..., records_already_paid: _Optional[int] = ..., tokens_spent: _Optional[str] = ...) -> None: ...
