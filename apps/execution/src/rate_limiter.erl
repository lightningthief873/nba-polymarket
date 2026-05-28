-module(rate_limiter).
-behaviour(gen_server).

-export([start_link/0, start/0]).
-export([check_and_consume/0, tokens/0, reset/0, sync/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(DEFAULT_RATE,  10).   %% tokens per second
-define(DEFAULT_BURST, 10).   %% max bucket depth

-record(st, {
    tokens      :: float(),
    rate        :: float(),
    max         :: float(),
    last_ns     :: integer()
}).

%% ---------------------------------------------------------------------------
%% Public API
%% ---------------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

-spec check_and_consume() -> ok | {error, rate_limited}.
check_and_consume() ->
    gen_server:call(?MODULE, check_and_consume).

-spec tokens() -> float().
tokens() ->
    gen_server:call(?MODULE, tokens).

%% Reset bucket to full — for test use only.
-spec reset() -> ok.
reset() ->
    gen_server:call(?MODULE, reset).

-spec sync() -> ok.
sync() ->
    gen_server:call(?MODULE, sync).

%% ---------------------------------------------------------------------------
%% gen_server callbacks
%% ---------------------------------------------------------------------------

init([]) ->
    Rate  = application:get_env(execution, rate_limit_per_sec, ?DEFAULT_RATE),
    Burst = application:get_env(execution, rate_limit_burst,   ?DEFAULT_BURST),
    {ok, #st{
        tokens  = float(Burst),
        rate    = float(Rate),
        max     = float(Burst),
        last_ns = erlang:monotonic_time(nanosecond)
    }}.

handle_call(check_and_consume, _From, St0) ->
    St1 = refill(St0),
    case St1#st.tokens >= 1.0 of
        true  -> {reply, ok,                    St1#st{tokens = St1#st.tokens - 1.0}};
        false -> {reply, {error, rate_limited}, St1}
    end;
handle_call(tokens, _From, St0) ->
    St1 = refill(St0),
    {reply, St1#st.tokens, St1};
handle_call(reset, _From, St) ->
    {reply, ok, St#st{tokens = St#st.max, last_ns = erlang:monotonic_time(nanosecond)}};
handle_call(sync, _From, St) ->
    {reply, ok, St};
handle_call(_Req, _From, St) ->
    {reply, {error, unknown}, St}.

handle_cast(_Msg, St) ->
    {noreply, St}.

handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) ->
    ok.

%% ---------------------------------------------------------------------------
%% Internal
%% ---------------------------------------------------------------------------

refill(#st{tokens = Tokens, rate = Rate, max = Max, last_ns = LastNs} = St) ->
    NowNs   = erlang:monotonic_time(nanosecond),
    Elapsed = NowNs - LastNs,
    Added   = Elapsed * Rate / 1.0e9,
    New     = min(Max, Tokens + Added),
    St#st{tokens = New, last_ns = NowNs}.
