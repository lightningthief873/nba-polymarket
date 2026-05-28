-module(kill_switch).

%% Two-layer kill switch (layer 1: Erlang flag via persistent_term).
%% Layer 2 (Polygon allowance revocation) is wired in Phase 3 Day 46.
%%
%% is_armed/0 is a sub-microsecond persistent_term read — safe to call on
%% every signal without any gen_server round-trip.

-export([is_armed/0, arm/0, disarm/0, last_changed/0]).

-define(STATE_KEY,   {?MODULE, state}).
-define(CHANGED_KEY, {?MODULE, last_changed_ns}).

-spec is_armed() -> boolean().
is_armed() ->
    persistent_term:get(?STATE_KEY, armed) =:= armed.

-spec arm() -> ok.
arm() ->
    set_state(armed).

-spec disarm() -> ok.
disarm() ->
    set_state(disarmed).

%% Returns nanosecond timestamp of the last arm/disarm call, or 0 if never changed.
-spec last_changed() -> non_neg_integer().
last_changed() ->
    persistent_term:get(?CHANGED_KEY, 0).

%% ---------------------------------------------------------------------------
%% Internal
%% ---------------------------------------------------------------------------

set_state(NewState) ->
    OldState = persistent_term:get(?STATE_KEY, armed),
    case NewState =:= OldState of
        true  -> ok;
        false ->
            NowNs = erlang:system_time(nanosecond),
            persistent_term:put(?STATE_KEY,   NewState),
            persistent_term:put(?CHANGED_KEY, NowNs),
            logger:warning("[kill_switch] state changed: ~w -> ~w", [OldState, NewState]),
            ok
    end.
