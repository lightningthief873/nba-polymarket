-module(signal_aggregator).
-behaviour(gen_server).

-export([start_link/0, start/0]).
-export([metrics/0, sync/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(st, {signal_count = 0}).

%% ---------------------------------------------------------------------------
%% Public API
%% ---------------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Unlinked start for use in tests.
start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

-spec metrics() -> map().
metrics() ->
    gen_server:call(?MODULE, metrics).

%% Flush gen_server mailbox — use in tests after publishing signals.
-spec sync() -> ok.
sync() ->
    gen_server:call(?MODULE, sync).

%% ---------------------------------------------------------------------------
%% gen_server callbacks
%% ---------------------------------------------------------------------------

init([]) ->
    ok = event_bus:subscribe(signal),
    {ok, #st{}}.

handle_call(metrics, _From, St) ->
    {reply, #{signal_count => St#st.signal_count}, St};
handle_call(sync, _From, St) ->
    {reply, ok, St};
handle_call(_Req, _From, St) ->
    {reply, {error, unknown}, St}.

handle_cast(_Msg, St) ->
    {noreply, St}.

handle_info({event, signal, Signal}, St) ->
    logger:info("[signal_aggregator] ~p", [Signal]),
    {noreply, St#st{signal_count = St#st.signal_count + 1}};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) ->
    ok.
