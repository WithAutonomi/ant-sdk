from antd._proto.antd.v1 import common_pb2 as _common_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class GetChunkRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class GetChunkResponse(_message.Message):
    __slots__ = ("data",)
    DATA_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    def __init__(self, data: _Optional[bytes] = ...) -> None: ...

class PutChunkRequest(_message.Message):
    __slots__ = ("data",)
    DATA_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    def __init__(self, data: _Optional[bytes] = ...) -> None: ...

class PutChunkResponse(_message.Message):
    __slots__ = ("cost", "address")
    COST_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    cost: _common_pb2.Cost
    address: str
    def __init__(self, cost: _Optional[_Union[_common_pb2.Cost, _Mapping]] = ..., address: _Optional[str] = ...) -> None: ...

class PrepareChunkRequest(_message.Message):
    __slots__ = ("data",)
    DATA_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    def __init__(self, data: _Optional[bytes] = ...) -> None: ...

class PrepareChunkResponse(_message.Message):
    __slots__ = ("address", "already_stored", "upload_id", "payment_type", "payments", "total_amount", "payment_vault_address", "payment_token_address", "rpc_url")
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    ALREADY_STORED_FIELD_NUMBER: _ClassVar[int]
    UPLOAD_ID_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    PAYMENTS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_AMOUNT_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_VAULT_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_TOKEN_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    RPC_URL_FIELD_NUMBER: _ClassVar[int]
    address: str
    already_stored: bool
    upload_id: str
    payment_type: str
    payments: _containers.RepeatedCompositeFieldContainer[_common_pb2.PaymentEntry]
    total_amount: str
    payment_vault_address: str
    payment_token_address: str
    rpc_url: str
    def __init__(self, address: _Optional[str] = ..., already_stored: bool = ..., upload_id: _Optional[str] = ..., payment_type: _Optional[str] = ..., payments: _Optional[_Iterable[_Union[_common_pb2.PaymentEntry, _Mapping]]] = ..., total_amount: _Optional[str] = ..., payment_vault_address: _Optional[str] = ..., payment_token_address: _Optional[str] = ..., rpc_url: _Optional[str] = ...) -> None: ...

class FinalizeChunkRequest(_message.Message):
    __slots__ = ("upload_id", "tx_hashes")
    class TxHashesEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    UPLOAD_ID_FIELD_NUMBER: _ClassVar[int]
    TX_HASHES_FIELD_NUMBER: _ClassVar[int]
    upload_id: str
    tx_hashes: _containers.ScalarMap[str, str]
    def __init__(self, upload_id: _Optional[str] = ..., tx_hashes: _Optional[_Mapping[str, str]] = ...) -> None: ...

class FinalizeChunkResponse(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...
