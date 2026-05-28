-module(strategy_runtime).
-behaviour(gen_server).

-export([start_link/3]).
-export([sync/1, get_info/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(REGISTRY, strategy_registry).
-define(TICK_MS,  100).

-record(st, {
    strategy_id,
    module,
    inner,
    sig_count = 0
}).

%% ---------------------------------------------------------------------------
%% Public API
%% ---------------------------------------------------------------------------

start_link(StrategyId, Module, Args) ->
    gen_server:start_link(?MODULE, {StrategyId, Module, Args}, []).

%% Flush the gen_server mailbox — use in tests after publishing events.
-spec sync(binary()) -> ok | not_found.
sync(StrategyId) ->
    case ets:lookup(?REGISTRY, StrategyId) of
        [{_, _, Pid}] -> gen_server:call(Pid, sync);
        []            -> not_found
    end.

-spec get_info(binary()) -> {binary(), module(), non_neg_integer()} | not_found.
get_info(StrategyId) ->
    case ets:lookup(?REGISTRY, StrategyId) of
        [{_, _, Pid}] -> gen_server:call(Pid, get_info);
        []            -> not_found
    end.

%% ---------------------------------------------------------------------------
%% gen_server callbacks
%% ---------------------------------------------------------------------------

init({StrategyId, Module, Args}) ->
    case Module:init(Args) of
        {ok, Inner} ->
            ok = event_bus:subscribe(market),
            ok = event_bus:subscribe(game),
            ets:insert(?REGISTRY, {StrategyId, Module, self()}),
            erlang:send_after(?TICK_MS, self(), clock_tick),
            {ok, #st{strategy_id = StrategyId, module = Module, inner = Inner}};
        {stop, Reason} ->
            {stop, Reason}
    end.

handle_call(sync, _From, St) ->
    {reply, ok, St};
handle_call(get_info, _From,
            #st{strategy_id = SId, module = Mod, sig_count = Cnt} = St) ->
    {reply, {SId, Mod, Cnt}, St};
handle_call(get_state, _From, #st{inner = Inner} = St) ->
    {reply, {ok, Inner}, St};
handle_call(_Req, _From, St) ->
    {reply, {error, unknown}, St}.

handle_cast(_Msg, St) ->
    {noreply, St}.

handle_info({event, market, Event}, #st{module = Mod, inner = Inner} = St) ->
    case Mod:on_market_event(Event, Inner) of
        {ok, Signals, NewInner} ->
            emit(Signals, St#st.strategy_id),
            {noreply, St#st{inner     = NewInner,
                            sig_count = St#st.sig_count + length(Signals)}};
        {stop, Reason, NewInner} ->
            {stop, Reason, St#st{inner = NewInner}}
    end;
handle_info({event, game, Event}, #st{module = Mod, inner = Inner} = St) ->
    {ok, Signals, NewInner} = Mod:on_game_event(Event, Inner),
    emit(Signals, St#st.strategy_id),
    {noreply, St#st{inner     = NewInner,
                    sig_count = St#st.sig_count + length(Signals)}};
handle_info(clock_tick, #st{module = Mod, inner = Inner} = St) ->
    NowNs = erlang:system_time(nanosecond),
    {ok, Signals, NewInner} = Mod:on_clock_tick(NowNs, Inner),
    emit(Signals, St#st.strategy_id),
    erlang:send_after(?TICK_MS, self(), clock_tick),
    {noreply, St#st{inner     = NewInner,
                    sig_count = St#st.sig_count + length(Signals)}};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(Reason, #st{strategy_id = SId, module = Mod, inner = Inner}) ->
    catch Mod:terminate(Reason, Inner),
    %% catch: ETS may be gone if strategy_supervisor crashed before us.
    catch ets:delete(?REGISTRY, SId),
    ok.

%% ---------------------------------------------------------------------------
%% Internal
%% ---------------------------------------------------------------------------

emit([], _SId) -> ok;
emit([Sig | Rest], SId) ->
    event_bus:publish(signal, Sig#{strategy_id => SId}),
    emit(Rest, SId).
