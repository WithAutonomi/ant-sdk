from antd._proto.antd.v1 import common_pb2 as _common_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class ListPointerKeysRequest(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...

class ListPointerKeysResponse(_message.Message):
    __slots__ = ("keys",)
    KEYS_FIELD_NUMBER: _ClassVar[int]
    keys: _containers.RepeatedCompositeFieldContainer[PointerKey]
    def __init__(self, keys: _Optional[_Iterable[_Union[PointerKey, _Mapping]]] = ...) -> None: ...

class PointerKey(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class PointerWriteRequest(_message.Message):
    __slots__ = ("owner", "target", "kind")
    OWNER_FIELD_NUMBER: _ClassVar[int]
    TARGET_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    owner: str
    target: str
    kind: str
    def __init__(self, owner: _Optional[str] = ..., target: _Optional[str] = ..., kind: _Optional[str] = ...) -> None: ...

class PointerWriteResponse(_message.Message):
    __slots__ = ("address", "state_id", "counter")
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    STATE_ID_FIELD_NUMBER: _ClassVar[int]
    COUNTER_FIELD_NUMBER: _ClassVar[int]
    address: str
    state_id: str
    counter: str
    def __init__(self, address: _Optional[str] = ..., state_id: _Optional[str] = ..., counter: _Optional[str] = ...) -> None: ...

class PointerTransferRequest(_message.Message):
    __slots__ = ("owner", "recipient")
    OWNER_FIELD_NUMBER: _ClassVar[int]
    RECIPIENT_FIELD_NUMBER: _ClassVar[int]
    owner: str
    recipient: str
    def __init__(self, owner: _Optional[str] = ..., recipient: _Optional[str] = ...) -> None: ...

class PointerTransferResponse(_message.Message):
    __slots__ = ("address", "state_id", "finality", "finality_error")
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    STATE_ID_FIELD_NUMBER: _ClassVar[int]
    FINALITY_FIELD_NUMBER: _ClassVar[int]
    FINALITY_ERROR_FIELD_NUMBER: _ClassVar[int]
    address: str
    state_id: str
    finality: PointerFinality
    finality_error: str
    def __init__(self, address: _Optional[str] = ..., state_id: _Optional[str] = ..., finality: _Optional[_Union[PointerFinality, _Mapping]] = ..., finality_error: _Optional[str] = ...) -> None: ...

class GetPointerRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class PointerRecord(_message.Message):
    __slots__ = ("address", "owner", "counter", "kind", "kind_tag", "target", "state_id", "is_final", "transferred_to")
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    OWNER_FIELD_NUMBER: _ClassVar[int]
    COUNTER_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    KIND_TAG_FIELD_NUMBER: _ClassVar[int]
    TARGET_FIELD_NUMBER: _ClassVar[int]
    STATE_ID_FIELD_NUMBER: _ClassVar[int]
    IS_FINAL_FIELD_NUMBER: _ClassVar[int]
    TRANSFERRED_TO_FIELD_NUMBER: _ClassVar[int]
    address: str
    owner: str
    counter: str
    kind: str
    kind_tag: int
    target: str
    state_id: str
    is_final: bool
    transferred_to: str
    def __init__(self, address: _Optional[str] = ..., owner: _Optional[str] = ..., counter: _Optional[str] = ..., kind: _Optional[str] = ..., kind_tag: _Optional[int] = ..., target: _Optional[str] = ..., state_id: _Optional[str] = ..., is_final: bool = ..., transferred_to: _Optional[str] = ...) -> None: ...

class ResolvePointerRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class PointerResolved(_message.Message):
    __slots__ = ("kind", "kind_tag", "target")
    KIND_FIELD_NUMBER: _ClassVar[int]
    KIND_TAG_FIELD_NUMBER: _ClassVar[int]
    TARGET_FIELD_NUMBER: _ClassVar[int]
    kind: str
    kind_tag: int
    target: str
    def __init__(self, kind: _Optional[str] = ..., kind_tag: _Optional[int] = ..., target: _Optional[str] = ...) -> None: ...

class PointerFinalityRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class PointerFinalState(_message.Message):
    __slots__ = ("state_id", "kind", "kind_tag", "target", "holders", "transferred_to")
    STATE_ID_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    KIND_TAG_FIELD_NUMBER: _ClassVar[int]
    TARGET_FIELD_NUMBER: _ClassVar[int]
    HOLDERS_FIELD_NUMBER: _ClassVar[int]
    TRANSFERRED_TO_FIELD_NUMBER: _ClassVar[int]
    state_id: str
    kind: str
    kind_tag: int
    target: str
    holders: int
    transferred_to: str
    def __init__(self, state_id: _Optional[str] = ..., kind: _Optional[str] = ..., kind_tag: _Optional[int] = ..., target: _Optional[str] = ..., holders: _Optional[int] = ..., transferred_to: _Optional[str] = ...) -> None: ...

class PointerFinality(_message.Message):
    __slots__ = ("address", "group", "answered", "status", "counter", "state", "states", "majority", "transferred_to")
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    GROUP_FIELD_NUMBER: _ClassVar[int]
    ANSWERED_FIELD_NUMBER: _ClassVar[int]
    STATUS_FIELD_NUMBER: _ClassVar[int]
    COUNTER_FIELD_NUMBER: _ClassVar[int]
    STATE_FIELD_NUMBER: _ClassVar[int]
    STATES_FIELD_NUMBER: _ClassVar[int]
    MAJORITY_FIELD_NUMBER: _ClassVar[int]
    TRANSFERRED_TO_FIELD_NUMBER: _ClassVar[int]
    address: str
    group: int
    answered: int
    status: str
    counter: str
    state: PointerFinalState
    states: _containers.RepeatedCompositeFieldContainer[PointerFinalState]
    majority: PointerFinalState
    transferred_to: str
    def __init__(self, address: _Optional[str] = ..., group: _Optional[int] = ..., answered: _Optional[int] = ..., status: _Optional[str] = ..., counter: _Optional[str] = ..., state: _Optional[_Union[PointerFinalState, _Mapping]] = ..., states: _Optional[_Iterable[_Union[PointerFinalState, _Mapping]]] = ..., majority: _Optional[_Union[PointerFinalState, _Mapping]] = ..., transferred_to: _Optional[str] = ...) -> None: ...

class PointerControllerRequest(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class PointerController(_message.Message):
    __slots__ = ("pointer", "transfers", "frozen")
    POINTER_FIELD_NUMBER: _ClassVar[int]
    TRANSFERS_FIELD_NUMBER: _ClassVar[int]
    FROZEN_FIELD_NUMBER: _ClassVar[int]
    pointer: str
    transfers: _containers.RepeatedScalarFieldContainer[str]
    frozen: bool
    def __init__(self, pointer: _Optional[str] = ..., transfers: _Optional[_Iterable[str]] = ..., frozen: bool = ...) -> None: ...

class PreparePointerRequest(_message.Message):
    __slots__ = ("owner", "op", "target", "kind", "recipient", "include_signed_quotes")
    OWNER_FIELD_NUMBER: _ClassVar[int]
    OP_FIELD_NUMBER: _ClassVar[int]
    TARGET_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    RECIPIENT_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_SIGNED_QUOTES_FIELD_NUMBER: _ClassVar[int]
    owner: str
    op: str
    target: str
    kind: str
    recipient: str
    include_signed_quotes: bool
    def __init__(self, owner: _Optional[str] = ..., op: _Optional[str] = ..., target: _Optional[str] = ..., kind: _Optional[str] = ..., recipient: _Optional[str] = ..., include_signed_quotes: bool = ...) -> None: ...

class PreparePointerResponse(_message.Message):
    __slots__ = ("upload_id", "op", "address", "state_id", "counter", "payment_type", "payments", "total_amount", "payment_vault_address", "payment_token_address", "rpc_url", "signed_quotes")
    UPLOAD_ID_FIELD_NUMBER: _ClassVar[int]
    OP_FIELD_NUMBER: _ClassVar[int]
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    STATE_ID_FIELD_NUMBER: _ClassVar[int]
    COUNTER_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    PAYMENTS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_AMOUNT_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_VAULT_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    PAYMENT_TOKEN_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    RPC_URL_FIELD_NUMBER: _ClassVar[int]
    SIGNED_QUOTES_FIELD_NUMBER: _ClassVar[int]
    upload_id: str
    op: str
    address: str
    state_id: str
    counter: str
    payment_type: str
    payments: _containers.RepeatedCompositeFieldContainer[_common_pb2.PaymentEntry]
    total_amount: str
    payment_vault_address: str
    payment_token_address: str
    rpc_url: str
    signed_quotes: _containers.RepeatedCompositeFieldContainer[_common_pb2.SignedQuoteEntry]
    def __init__(self, upload_id: _Optional[str] = ..., op: _Optional[str] = ..., address: _Optional[str] = ..., state_id: _Optional[str] = ..., counter: _Optional[str] = ..., payment_type: _Optional[str] = ..., payments: _Optional[_Iterable[_Union[_common_pb2.PaymentEntry, _Mapping]]] = ..., total_amount: _Optional[str] = ..., payment_vault_address: _Optional[str] = ..., payment_token_address: _Optional[str] = ..., rpc_url: _Optional[str] = ..., signed_quotes: _Optional[_Iterable[_Union[_common_pb2.SignedQuoteEntry, _Mapping]]] = ...) -> None: ...

class FinalizePointerRequest(_message.Message):
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

class FinalizePointerResponse(_message.Message):
    __slots__ = ("address", "state_id", "counter", "finality")
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    STATE_ID_FIELD_NUMBER: _ClassVar[int]
    COUNTER_FIELD_NUMBER: _ClassVar[int]
    FINALITY_FIELD_NUMBER: _ClassVar[int]
    address: str
    state_id: str
    counter: str
    finality: PointerFinality
    def __init__(self, address: _Optional[str] = ..., state_id: _Optional[str] = ..., counter: _Optional[str] = ..., finality: _Optional[_Union[PointerFinality, _Mapping]] = ...) -> None: ...
