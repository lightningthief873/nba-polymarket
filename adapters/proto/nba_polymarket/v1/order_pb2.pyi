from nba_polymarket.v1 import common_pb2 as _common_pb2
from nba_polymarket.v1 import market_pb2 as _market_pb2
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class OrderType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    ORDER_TYPE_UNSPECIFIED: _ClassVar[OrderType]
    ORDER_TYPE_GTC: _ClassVar[OrderType]
    ORDER_TYPE_FOK: _ClassVar[OrderType]
    ORDER_TYPE_IOC: _ClassVar[OrderType]

class OrderStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    ORDER_STATUS_UNSPECIFIED: _ClassVar[OrderStatus]
    ORDER_STATUS_PENDING: _ClassVar[OrderStatus]
    ORDER_STATUS_OPEN: _ClassVar[OrderStatus]
    ORDER_STATUS_PARTIALLY_FILLED: _ClassVar[OrderStatus]
    ORDER_STATUS_FILLED: _ClassVar[OrderStatus]
    ORDER_STATUS_CANCELED: _ClassVar[OrderStatus]
    ORDER_STATUS_REJECTED: _ClassVar[OrderStatus]
ORDER_TYPE_UNSPECIFIED: OrderType
ORDER_TYPE_GTC: OrderType
ORDER_TYPE_FOK: OrderType
ORDER_TYPE_IOC: OrderType
ORDER_STATUS_UNSPECIFIED: OrderStatus
ORDER_STATUS_PENDING: OrderStatus
ORDER_STATUS_OPEN: OrderStatus
ORDER_STATUS_PARTIALLY_FILLED: OrderStatus
ORDER_STATUS_FILLED: OrderStatus
ORDER_STATUS_CANCELED: OrderStatus
ORDER_STATUS_REJECTED: OrderStatus

class Order(_message.Message):
    __slots__ = ("meta", "order_id", "strategy_id", "condition_id", "token_id", "side", "type", "price", "size", "status")
    META_FIELD_NUMBER: _ClassVar[int]
    ORDER_ID_FIELD_NUMBER: _ClassVar[int]
    STRATEGY_ID_FIELD_NUMBER: _ClassVar[int]
    CONDITION_ID_FIELD_NUMBER: _ClassVar[int]
    TOKEN_ID_FIELD_NUMBER: _ClassVar[int]
    SIDE_FIELD_NUMBER: _ClassVar[int]
    TYPE_FIELD_NUMBER: _ClassVar[int]
    PRICE_FIELD_NUMBER: _ClassVar[int]
    SIZE_FIELD_NUMBER: _ClassVar[int]
    STATUS_FIELD_NUMBER: _ClassVar[int]
    meta: _common_pb2.EventMetadata
    order_id: str
    strategy_id: str
    condition_id: str
    token_id: str
    side: _market_pb2.Side
    type: OrderType
    price: float
    size: float
    status: OrderStatus
    def __init__(self, meta: _Optional[_Union[_common_pb2.EventMetadata, _Mapping]] = ..., order_id: _Optional[str] = ..., strategy_id: _Optional[str] = ..., condition_id: _Optional[str] = ..., token_id: _Optional[str] = ..., side: _Optional[_Union[_market_pb2.Side, str]] = ..., type: _Optional[_Union[OrderType, str]] = ..., price: _Optional[float] = ..., size: _Optional[float] = ..., status: _Optional[_Union[OrderStatus, str]] = ...) -> None: ...

class Fill(_message.Message):
    __slots__ = ("meta", "order_id", "price", "size", "fee")
    META_FIELD_NUMBER: _ClassVar[int]
    ORDER_ID_FIELD_NUMBER: _ClassVar[int]
    PRICE_FIELD_NUMBER: _ClassVar[int]
    SIZE_FIELD_NUMBER: _ClassVar[int]
    FEE_FIELD_NUMBER: _ClassVar[int]
    meta: _common_pb2.EventMetadata
    order_id: str
    price: float
    size: float
    fee: float
    def __init__(self, meta: _Optional[_Union[_common_pb2.EventMetadata, _Mapping]] = ..., order_id: _Optional[str] = ..., price: _Optional[float] = ..., size: _Optional[float] = ..., fee: _Optional[float] = ...) -> None: ...

class Position(_message.Message):
    __slots__ = ("condition_id", "token_id", "size", "avg_entry_price", "unrealized_pnl", "realized_pnl")
    CONDITION_ID_FIELD_NUMBER: _ClassVar[int]
    TOKEN_ID_FIELD_NUMBER: _ClassVar[int]
    SIZE_FIELD_NUMBER: _ClassVar[int]
    AVG_ENTRY_PRICE_FIELD_NUMBER: _ClassVar[int]
    UNREALIZED_PNL_FIELD_NUMBER: _ClassVar[int]
    REALIZED_PNL_FIELD_NUMBER: _ClassVar[int]
    condition_id: str
    token_id: str
    size: float
    avg_entry_price: float
    unrealized_pnl: float
    realized_pnl: float
    def __init__(self, condition_id: _Optional[str] = ..., token_id: _Optional[str] = ..., size: _Optional[float] = ..., avg_entry_price: _Optional[float] = ..., unrealized_pnl: _Optional[float] = ..., realized_pnl: _Optional[float] = ...) -> None: ...
