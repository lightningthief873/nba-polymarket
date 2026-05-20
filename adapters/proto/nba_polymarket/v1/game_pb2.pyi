from nba_polymarket.v1 import common_pb2 as _common_pb2
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class GamePhase(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    GAME_PHASE_UNSPECIFIED: _ClassVar[GamePhase]
    GAME_PHASE_PRE_GAME: _ClassVar[GamePhase]
    GAME_PHASE_IN_PROGRESS: _ClassVar[GamePhase]
    GAME_PHASE_HALFTIME: _ClassVar[GamePhase]
    GAME_PHASE_QUARTER_BREAK: _ClassVar[GamePhase]
    GAME_PHASE_FINAL: _ClassVar[GamePhase]
GAME_PHASE_UNSPECIFIED: GamePhase
GAME_PHASE_PRE_GAME: GamePhase
GAME_PHASE_IN_PROGRESS: GamePhase
GAME_PHASE_HALFTIME: GamePhase
GAME_PHASE_QUARTER_BREAK: GamePhase
GAME_PHASE_FINAL: GamePhase

class GameEvent(_message.Message):
    __slots__ = ("meta", "game_id", "home_team", "away_team", "home_score", "away_score", "period", "game_clock_ms", "phase", "possession_team")
    META_FIELD_NUMBER: _ClassVar[int]
    GAME_ID_FIELD_NUMBER: _ClassVar[int]
    HOME_TEAM_FIELD_NUMBER: _ClassVar[int]
    AWAY_TEAM_FIELD_NUMBER: _ClassVar[int]
    HOME_SCORE_FIELD_NUMBER: _ClassVar[int]
    AWAY_SCORE_FIELD_NUMBER: _ClassVar[int]
    PERIOD_FIELD_NUMBER: _ClassVar[int]
    GAME_CLOCK_MS_FIELD_NUMBER: _ClassVar[int]
    PHASE_FIELD_NUMBER: _ClassVar[int]
    POSSESSION_TEAM_FIELD_NUMBER: _ClassVar[int]
    meta: _common_pb2.EventMetadata
    game_id: str
    home_team: str
    away_team: str
    home_score: int
    away_score: int
    period: int
    game_clock_ms: int
    phase: GamePhase
    possession_team: str
    def __init__(self, meta: _Optional[_Union[_common_pb2.EventMetadata, _Mapping]] = ..., game_id: _Optional[str] = ..., home_team: _Optional[str] = ..., away_team: _Optional[str] = ..., home_score: _Optional[int] = ..., away_score: _Optional[int] = ..., period: _Optional[int] = ..., game_clock_ms: _Optional[int] = ..., phase: _Optional[_Union[GamePhase, str]] = ..., possession_team: _Optional[str] = ...) -> None: ...
