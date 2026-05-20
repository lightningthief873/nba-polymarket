from nba_polymarket.v1 import common_pb2 as _common_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class Side(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SIDE_UNSPECIFIED: _ClassVar[Side]
    SIDE_BUY: _ClassVar[Side]
    SIDE_SELL: _ClassVar[Side]
SIDE_UNSPECIFIED: Side
SIDE_BUY: Side
SIDE_SELL: Side

class PriceLevel(_message.Message):
    __slots__ = ("price", "size")
    PRICE_FIELD_NUMBER: _ClassVar[int]
    SIZE_FIELD_NUMBER: _ClassVar[int]
    price: float
    size: float
    def __init__(self, price: _Optional[float] = ..., size: _Optional[float] = ...) -> None: ...

class MarketEvent(_message.Message):
    __slots__ = ("meta", "condition_id", "token_id", "bids", "asks", "last_trade_price", "last_trade_size")
    META_FIELD_NUMBER: _ClassVar[int]
    CONDITION_ID_FIELD_NUMBER: _ClassVar[int]
    TOKEN_ID_FIELD_NUMBER: _ClassVar[int]
    BIDS_FIELD_NUMBER: _ClassVar[int]
    ASKS_FIELD_NUMBER: _ClassVar[int]
    LAST_TRADE_PRICE_FIELD_NUMBER: _ClassVar[int]
    LAST_TRADE_SIZE_FIELD_NUMBER: _ClassVar[int]
    meta: _common_pb2.EventMetadata
    condition_id: str
    token_id: str
    bids: _containers.RepeatedCompositeFieldContainer[PriceLevel]
    asks: _containers.RepeatedCompositeFieldContainer[PriceLevel]
    last_trade_price: float
    last_trade_size: float
    def __init__(self, meta: _Optional[_Union[_common_pb2.EventMetadata, _Mapping]] = ..., condition_id: _Optional[str] = ..., token_id: _Optional[str] = ..., bids: _Optional[_Iterable[_Union[PriceLevel, _Mapping]]] = ..., asks: _Optional[_Iterable[_Union[PriceLevel, _Mapping]]] = ..., last_trade_price: _Optional[float] = ..., last_trade_size: _Optional[float] = ...) -> None: ...
