from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class Source(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SOURCE_UNSPECIFIED: _ClassVar[Source]
    SOURCE_POLYMARKET_WS: _ClassVar[Source]
    SOURCE_POLYMARKET_REST: _ClassVar[Source]
    SOURCE_NBA_API: _ClassVar[Source]
    SOURCE_ESPN: _ClassVar[Source]
    SOURCE_SIMULATOR_REPLAY: _ClassVar[Source]
    SOURCE_SIMULATOR_SYNTHETIC: _ClassVar[Source]
SOURCE_UNSPECIFIED: Source
SOURCE_POLYMARKET_WS: Source
SOURCE_POLYMARKET_REST: Source
SOURCE_NBA_API: Source
SOURCE_ESPN: Source
SOURCE_SIMULATOR_REPLAY: Source
SOURCE_SIMULATOR_SYNTHETIC: Source

class EventMetadata(_message.Message):
    __slots__ = ("timestamp_ns", "ingested_ns", "source", "trace_id")
    TIMESTAMP_NS_FIELD_NUMBER: _ClassVar[int]
    INGESTED_NS_FIELD_NUMBER: _ClassVar[int]
    SOURCE_FIELD_NUMBER: _ClassVar[int]
    TRACE_ID_FIELD_NUMBER: _ClassVar[int]
    timestamp_ns: int
    ingested_ns: int
    source: Source
    trace_id: str
    def __init__(self, timestamp_ns: _Optional[int] = ..., ingested_ns: _Optional[int] = ..., source: _Optional[_Union[Source, str]] = ..., trace_id: _Optional[str] = ...) -> None: ...
