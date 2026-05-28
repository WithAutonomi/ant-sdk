from antd._proto.antd.v1 import common_pb2 as _common_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class PrepareFileUploadRequest(_message.Message):
    __slots__ = ("path", "visibility")
    PATH_FIELD_NUMBER: _ClassVar[int]
    VISIBILITY_FIELD_NUMBER: _ClassVar[int]
    path: str
    visibility: str
    def __init__(self, path: _Optional[str] = ..., visibility: _Optional[str] = ...) -> None: ...

class PrepareDataUploadRequest(_message.Message):
    __slots__ = ("data", "visibility")
    DATA_FIELD_NUMBER: _ClassVar[int]
    VISIBILITY_FIELD_NUMBER: _ClassVar[int]
    data: bytes
    visibility: str
    def __init__(self, data: _Optional[bytes] = ..., visibility: _Optional[str] = ...) -> None: ...

class PrepareUploadResponse(_message.Message):
    __slots__ = ("upload_id", "payment_type", "payments", "depth", "pool_commitments", "merkle_payment_timestamp", "total_amount", "payment_vault_address", "payment_token_address", "rpc_url")
    UPLOAD_ID_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    PAYMENTS_FIELD_NUMBER: _ClassVar[int]
    DEPTH_FIELD_NUMBER: _ClassVar[int]
    POOL_COMMITMENTS_FIELD_NUMBER: _ClassVar[int]
    MERKLE_PAYMENT_TIMESTAMP_FIELD_NUMBER: _ClassVar[int]
    TOTAL_AMOUNT_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_VAULT_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_TOKEN_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    RPC_URL_FIELD_NUMBER: _ClassVar[int]
    upload_id: str
    payment_type: str
    payments: _containers.RepeatedCompositeFieldContainer[_common_pb2.PaymentEntry]
    depth: int
    pool_commitments: _containers.RepeatedCompositeFieldContainer[PoolCommitmentEntry]
    merkle_payment_timestamp: int
    total_amount: str
    payment_vault_address: str
    payment_token_address: str
    rpc_url: str
    def __init__(self, upload_id: _Optional[str] = ..., payment_type: _Optional[str] = ..., payments: _Optional[_Iterable[_Union[_common_pb2.PaymentEntry, _Mapping]]] = ..., depth: _Optional[int] = ..., pool_commitments: _Optional[_Iterable[_Union[PoolCommitmentEntry, _Mapping]]] = ..., merkle_payment_timestamp: _Optional[int] = ..., total_amount: _Optional[str] = ..., payment_vault_address: _Optional[str] = ..., payment_token_address: _Optional[str] = ..., rpc_url: _Optional[str] = ...) -> None: ...

class PoolCommitmentEntry(_message.Message):
    __slots__ = ("pool_hash", "candidates")
    POOL_HASH_FIELD_NUMBER: _ClassVar[int]
    CANDIDATES_FIELD_NUMBER: _ClassVar[int]
    pool_hash: str
    candidates: _containers.RepeatedCompositeFieldContainer[CandidateNodeEntry]
    def __init__(self, pool_hash: _Optional[str] = ..., candidates: _Optional[_Iterable[_Union[CandidateNodeEntry, _Mapping]]] = ...) -> None: ...

class CandidateNodeEntry(_message.Message):
    __slots__ = ("rewards_address", "amount")
    REWARDS_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    AMOUNT_FIELD_NUMBER: _ClassVar[int]
    rewards_address: str
    amount: str
    def __init__(self, rewards_address: _Optional[str] = ..., amount: _Optional[str] = ...) -> None: ...

class FinalizeUploadRequest(_message.Message):
    __slots__ = ("upload_id", "tx_hashes", "winner_pool_hash", "store_data_map")
    class TxHashesEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    UPLOAD_ID_FIELD_NUMBER: _ClassVar[int]
    TX_HASHES_FIELD_NUMBER: _ClassVar[int]
    WINNER_POOL_HASH_FIELD_NUMBER: _ClassVar[int]
    STORE_DATA_MAP_FIELD_NUMBER: _ClassVar[int]
    upload_id: str
    tx_hashes: _containers.ScalarMap[str, str]
    winner_pool_hash: str
    store_data_map: bool
    def __init__(self, upload_id: _Optional[str] = ..., tx_hashes: _Optional[_Mapping[str, str]] = ..., winner_pool_hash: _Optional[str] = ..., store_data_map: bool = ...) -> None: ...

class FinalizeUploadResponse(_message.Message):
    __slots__ = ("data_map", "address", "data_map_address", "chunks_stored")
    DATA_MAP_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    DATA_MAP_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    CHUNKS_STORED_FIELD_NUMBER: _ClassVar[int]
    data_map: str
    address: str
    data_map_address: str
    chunks_stored: int
    def __init__(self, data_map: _Optional[str] = ..., address: _Optional[str] = ..., data_map_address: _Optional[str] = ..., chunks_stored: _Optional[int] = ...) -> None: ...
