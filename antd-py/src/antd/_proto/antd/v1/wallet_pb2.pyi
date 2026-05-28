from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class GetWalletAddressRequest(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...

class GetWalletAddressResponse(_message.Message):
    __slots__ = ("address",)
    ADDRESS_FIELD_NUMBER: _ClassVar[int]
    address: str
    def __init__(self, address: _Optional[str] = ...) -> None: ...

class GetWalletBalanceRequest(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...

class GetWalletBalanceResponse(_message.Message):
    __slots__ = ("balance", "gas_balance")
    BALANCE_FIELD_NUMBER: _ClassVar[int]
    GAS_BALANCE_FIELD_NUMBER: _ClassVar[int]
    balance: str
    gas_balance: str
    def __init__(self, balance: _Optional[str] = ..., gas_balance: _Optional[str] = ...) -> None: ...

class WalletApproveRequest(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...

class WalletApproveResponse(_message.Message):
    __slots__ = ("approved",)
    APPROVED_FIELD_NUMBER: _ClassVar[int]
    approved: bool
    def __init__(self, approved: bool = ...) -> None: ...
