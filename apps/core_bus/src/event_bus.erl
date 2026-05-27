%% ADR: gproc chosen over pg/pg2 — local-first, property-key API avoids
%% name clashes when event types expand, and gproc is a hard dep already.
-module(event_bus).

-export([subscribe/1, publish/2, metrics/0]).

%% Register the calling process as a subscriber for EventType.
%% Messages arrive as {event, EventType, Payload}.
-spec subscribe(atom()) -> ok.
subscribe(EventType) ->
    true = gproc:reg({p, l, {event, EventType}}),
    ok.

%% Publish Payload to all current subscribers for EventType.
-spec publish(atom(), term()) -> ok.
publish(EventType, Payload) ->
    gproc:send({p, l, {event, EventType}}, {event, EventType, Payload}),
    ok.

%% Delegate to ingest_subscriber for ZMQ ingestion metrics.
-spec metrics() -> map().
metrics() ->
    ingest_subscriber:metrics().
