-module(strategy_supervisor).
-behaviour(supervisor).

-export([start_link/0]).
-export([add_strategy/3, remove_strategy/1, list_strategies/0, get_strategy_state/1]).
-export([init/1]).

%% Shared with strategy_runtime — both reference this atom directly.
-define(REGISTRY, strategy_registry).

%% ---------------------------------------------------------------------------
%% Public API
%% ---------------------------------------------------------------------------

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec add_strategy(binary(), module(), term()) -> {ok, pid()} | {error, term()}.
add_strategy(StrategyId, Module, Args) ->
    supervisor:start_child(?MODULE, [StrategyId, Module, Args]).

-spec remove_strategy(binary()) -> ok | not_found.
remove_strategy(StrategyId) ->
    case ets:lookup(?REGISTRY, StrategyId) of
        [{_, _, Pid}] ->
            %% Delete registry entry first so terminate/2 in strategy_runtime
            %% does not attempt a redundant delete under the same key.
            ets:delete(?REGISTRY, StrategyId),
            case supervisor:terminate_child(?MODULE, Pid) of
                ok               -> ok;
                {error, not_found} -> ok   %% already dead / restarting
            end;
        [] ->
            not_found
    end.

-spec list_strategies() -> [{binary(), module(), pid(), running}].
list_strategies() ->
    [{SId, Mod, Pid, running}
     || {SId, Mod, Pid} <- ets:tab2list(?REGISTRY),
        is_process_alive(Pid)].

-spec get_strategy_state(binary()) -> {ok, term()} | not_found.
get_strategy_state(StrategyId) ->
    case ets:lookup(?REGISTRY, StrategyId) of
        [{_, _, Pid}] -> gen_server:call(Pid, get_state);
        []            -> not_found
    end.

%% ---------------------------------------------------------------------------
%% Supervisor callbacks
%% ---------------------------------------------------------------------------

init([]) ->
    %% ETS table owned by this supervisor process; destroyed on supervisor exit.
    ?REGISTRY = ets:new(?REGISTRY, [named_table, set, public,
                                    {keypos, 1},
                                    {read_concurrency, true},
                                    {write_concurrency, true}]),
    SupFlags  = #{strategy => simple_one_for_one, intensity => 10, period => 60},
    ChildSpec = #{id      => strategy_runtime,
                 start   => {strategy_runtime, start_link, []},
                 restart => transient,
                 type    => worker},
    {ok, {SupFlags, [ChildSpec]}}.
