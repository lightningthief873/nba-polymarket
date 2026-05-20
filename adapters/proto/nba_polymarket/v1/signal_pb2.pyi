from nba_polymarket.v1 import common_pb2 as _common_pb2
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class SignalAction(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SIGNAL_ACTION_UNSPECIFIED: _ClassVar[SignalAction]
    SIGNAL_ACTION_BUY: _ClassVar[SignalAction]
    SIGNAL_ACTION_SELL: _ClassVar[SignalAction]
    SIGNAL_ACTION_CLOSE: _ClassVar[SignalAction]
    SIGNAL_ACTION_HOLD: _ClassVar[SignalAction]
SIGNAL_ACTION_UNSPECIFIED: SignalAction
SIGNAL_ACTION_BUY: SignalAction
SIGNAL_ACTION_SELL: SignalAction
SIGNAL_ACTION_CLOSE: SignalAction
SIGNAL_ACTION_HOLD: SignalAction

class Signal(_message.Message):
    __slots__ = ("meta", "strategy_id", "condition_id", "token_id", "action", "target_price", "size", "confidence", "reason")
    META_FIELD_NUMBER: _ClassVar[int]
    STRATEGY_ID_FIELD_NUMBER: _ClassVar[int]
    CONDITION_ID_FIELD_NUMBER: _ClassVar[int]
    TOKEN_ID_FIELD_NUMBER: _ClassVar[int]
    ACTION_FIELD_NUMBER: _ClassVar[int]
    TARGET_PRICE_FIELD_NUMBER: _ClassVar[int]
    SIZE_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    REASON_FIELD_NUMBER: _ClassVar[int]
    meta: _common_pb2.EventMetadata
    strategy_id: str
    condition_id: str
    token_id: str
    action: SignalAction
    target_price: float
    size: float
    confidence: float
    reason: str
    def __init__(self, meta: _Optional[_Union[_common_pb2.EventMetadata, _Mapping]] = ..., strategy_id: _Optional[str] = ..., condition_id: _Optional[str] = ..., token_id: _Optional[str] = ..., action: _Optional[_Union[SignalAction, str]] = ..., target_price: _Optional[float] = ..., size: _Optional[float] = ..., confidence: _Optional[float] = ..., reason: _Optional[str] = ...) -> None: ...
