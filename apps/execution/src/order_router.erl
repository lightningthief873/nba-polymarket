-module(order_router).
-behaviour(gen_server).

-export([start_link/0, start/0]).
-export([metrics/0, sync/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(st, {
    accepted = 0,
    rejected = 0,
    config   = #{}
}).

-define(DEFAULT_CONFIG, #{
    max_position_per_token    => 100.0,
    max_position_per_strategy => 500.0,
    max_global_exposure       => 1000.0,
    min_order_size            => 5.0
}).

%% ---------------------------------------------------------------------------
%% Public API
%% ---------------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

-spec metrics() -> #{accepted := non_neg_integer(), rejected := non_neg_integer()}.
metrics() ->
    gen_server:call(?MODULE, metrics).

-spec sync() -> ok.
sync() ->
    gen_server:call(?MODULE, sync).

%% ---------------------------------------------------------------------------
%% gen_server callbacks
%% ---------------------------------------------------------------------------

init([]) ->
    Config = maps:merge(?DEFAULT_CONFIG, #{
        max_position_per_token    => application:get_env(execution, max_position_per_token,    100.0),
        max_position_per_strategy => application:get_env(execution, max_position_per_strategy, 500.0),
        max_global_exposure       => application:get_env(execution, max_global_exposure,       1000.0),
        min_order_size            => application:get_env(execution, min_order_size,            5.0)
    }),
    ok = event_bus:subscribe(signal),
    {ok, #st{config = Config}}.

handle_call(metrics, _From, #st{accepted = A, rejected = R} = St) ->
    {reply, #{accepted => A, rejected => R}, St};
handle_call(sync, _From, St) ->
    {reply, ok, St};
handle_call(_Req, _From, St) ->
    {reply, {error, unknown}, St}.

handle_cast(_Msg, St) ->
    {noreply, St}.

handle_info({event, signal, Signal}, St) ->
    {noreply, route(Signal, St)};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) ->
    ok.

%% ---------------------------------------------------------------------------
%% Internal
%% ---------------------------------------------------------------------------

route(Signal, #st{config = Cfg, accepted = Acc, rejected = Rej} = St) ->
    case kill_switch:is_armed() of
        false ->
            logger:warning("[order_router] kill switch disarmed, rejecting signal ~p",
                           [maps:get(strategy_id, Signal, unknown)]),
            St#st{rejected = Rej + 1};
        true ->
            case rate_limiter:check_and_consume() of
                {error, rate_limited} ->
                    logger:debug("[order_router] rate limited, dropping signal"),
                    St#st{rejected = Rej + 1};
                ok ->
                    StrategyId  = maps:get(strategy_id,  Signal, <<>>),
                    ConditionId = maps:get(condition_id, Signal, <<>>),
                    TokenId     = maps:get(token_id,     Signal, <<>>),
                    TokenShares = case position_tracker:get_position(StrategyId, ConditionId, TokenId) of
                        {ok, Pos} -> maps:get(shares, Pos, 0.0);
                        not_found -> 0.0
                    end,
                    StratTotal  = position_tracker:get_strategy_total(StrategyId),
                    GlobalTotal = position_tracker:get_global_total(),
                    Context = #{
                        token_shares       => TokenShares,
                        strategy_net_exposure => maps:get(net_exposure, StratTotal,  0.0),
                        global_net_exposure   => maps:get(net_exposure, GlobalTotal, 0.0)
                    },
                    case risk_check:check(Signal, Context, Cfg) of
                        {reject, Reason} ->
                            logger:info("[order_router] risk rejected (~w) signal from ~p",
                                        [Reason, StrategyId]),
                            St#st{rejected = Rej + 1};
                        ok ->
                            Order = build_order(Signal),
                            event_bus:publish(order, Order),
                            logger:debug("[order_router] accepted order ~p", [maps:get(order_id, Order)]),
                            St#st{accepted = Acc + 1}
                    end
            end
    end.

build_order(Signal) ->
    #{
        order_id     => uuid_v7(),
        strategy_id  => maps:get(strategy_id,  Signal, <<>>),
        condition_id => maps:get(condition_id, Signal, <<>>),
        token_id     => maps:get(token_id,     Signal, <<>>),
        side         => action_to_side(maps:get(action, Signal, 'SIGNAL_ACTION_BUY')),
        price        => maps:get(target_price, Signal, 0.5),
        size         => maps:get(size,         Signal, 10.0),
        order_type   => maps:get(order_type,   Signal, gtc),
        timestamp_ns => erlang:system_time(nanosecond)
    }.

action_to_side('SIGNAL_ACTION_BUY')  -> buy;
action_to_side('SIGNAL_ACTION_SELL') -> sell;
action_to_side(_)                    -> buy.

%% UUID v7: 48-bit ms timestamp | 4-bit version=7 | 12-bit rand | 2-bit variant=2 | 62-bit rand
uuid_v7() ->
    TsMs = erlang:system_time(millisecond),
    <<RandA:12, RandB:62, _:6>> = crypto:strong_rand_bytes(10),
    <<B1:32, B2:16, B3:16, B4:16, B5:48>> = <<TsMs:48, 7:4, RandA:12, 2:2, RandB:62>>,
    list_to_binary(
        io_lib:format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
                      [B1, B2, B3, B4, B5])).
