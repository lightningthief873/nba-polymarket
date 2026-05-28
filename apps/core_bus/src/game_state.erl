-module(game_state).
-behaviour(gen_server).

-export([start_link/0, start/0]).
-export([get_game/1, get_clock/1, get_score/1, all_games/0, sync/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TABLE,      game_state).
-define(NBA_QTR_MS, 720_000).   %% 12 min per quarter in ms
-define(LATE_MS,    120_000).   %% "late game" threshold: 2 min remaining

-record(grow, {
    game_id,
    home_team         = <<>>,
    away_team         = <<>>,
    home_score        = 0,
    away_score        = 0,
    period            = 0,
    game_clock_ms     = 0,
    phase             = 'GAME_PHASE_UNSPECIFIED',
    possession_team   = <<>>,
    last_update_ns    = 0,
    time_remaining_ms = 0,
    score_diff        = 0,
    late_game_flag    = false,
    update_count      = 0
}).

%% ---------------------------------------------------------------------------
%% Public API (reads go directly to ETS)
%% ---------------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

-spec get_game(binary()) -> {ok, map()} | not_found.
get_game(GameId) ->
    case ets:lookup(?TABLE, GameId) of
        [R] -> {ok, row_to_map(R)};
        []  -> not_found
    end.

-spec get_clock(binary()) -> {ok, {integer(), integer()}} | not_found.
get_clock(GameId) ->
    case ets:lookup(?TABLE, GameId) of
        [R] -> {ok, {R#grow.period, R#grow.game_clock_ms}};
        []  -> not_found
    end.

-spec get_score(binary()) -> {ok, {integer(), integer()}} | not_found.
get_score(GameId) ->
    case ets:lookup(?TABLE, GameId) of
        [R] -> {ok, {R#grow.home_score, R#grow.away_score}};
        []  -> not_found
    end.

-spec all_games() -> [map()].
all_games() ->
    [row_to_map(R) || R <- ets:tab2list(?TABLE)].

-spec sync() -> ok.
sync() ->
    gen_server:call(?MODULE, sync).

%% ---------------------------------------------------------------------------
%% gen_server callbacks
%% ---------------------------------------------------------------------------

init([]) ->
    ?TABLE = ets:new(?TABLE, [named_table, set, public,
                              {keypos, 2},
                              {read_concurrency, true},
                              {write_concurrency, true}]),
    ok = event_bus:subscribe(game),
    {ok, #{}}.

handle_call(sync, _From, State) ->
    {reply, ok, State};
handle_call(_Req, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({event, game, Event}, State) ->
    NowNs = erlang:system_time(nanosecond),
    process_event(Event, NowNs),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%% ---------------------------------------------------------------------------
%% Internal
%% ---------------------------------------------------------------------------

process_event(Event, NowNs) ->
    GameId    = maps:get(game_id,       Event, <<>>),
    Period    = maps:get(period,        Event, 0),
    ClockMs   = maps:get(game_clock_ms, Event, 0),
    HomeScore = maps:get(home_score,    Event, 0),
    AwayScore = maps:get(away_score,    Event, 0),

    Existing = case ets:lookup(?TABLE, GameId) of
        [R] -> R;
        []  -> #grow{game_id = GameId}
    end,

    Row = Existing#grow{
        home_team         = maps:get(home_team,       Event, Existing#grow.home_team),
        away_team         = maps:get(away_team,       Event, Existing#grow.away_team),
        home_score        = HomeScore,
        away_score        = AwayScore,
        period            = Period,
        game_clock_ms     = ClockMs,
        phase             = maps:get(phase,           Event, Existing#grow.phase),
        possession_team   = maps:get(possession_team, Event, Existing#grow.possession_team),
        last_update_ns    = NowNs,
        time_remaining_ms = time_remaining_ms(Period, ClockMs),
        score_diff        = HomeScore - AwayScore,
        late_game_flag    = is_late_game(Period, ClockMs),
        update_count      = Existing#grow.update_count + 1
    },
    ets:insert(?TABLE, Row).

%% Regulation: (4 - period) full quarters + current clock.
%% OT / pre-game: just return the clock value.
time_remaining_ms(Period, ClockMs) when Period >= 1, Period =< 4 ->
    (4 - Period) * ?NBA_QTR_MS + ClockMs;
time_remaining_ms(_Period, ClockMs) ->
    max(0, ClockMs).

is_late_game(4, ClockMs) when ClockMs =< ?LATE_MS -> true;
is_late_game(_, _)                                  -> false.

row_to_map(#grow{} = R) ->
    #{game_id           => R#grow.game_id,
      home_team         => R#grow.home_team,
      away_team         => R#grow.away_team,
      home_score        => R#grow.home_score,
      away_score        => R#grow.away_score,
      period            => R#grow.period,
      game_clock_ms     => R#grow.game_clock_ms,
      phase             => R#grow.phase,
      possession_team   => R#grow.possession_team,
      last_update_ns    => R#grow.last_update_ns,
      time_remaining_ms => R#grow.time_remaining_ms,
      score_diff        => R#grow.score_diff,
      late_game_flag    => R#grow.late_game_flag,
      update_count      => R#grow.update_count}.
