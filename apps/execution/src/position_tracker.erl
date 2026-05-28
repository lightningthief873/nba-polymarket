-module(position_tracker).
-behaviour(gen_server).

-export([start_link/0, start/0]).
-export([get_position/3, get_strategy_total/1, get_global_total/0, reset/0, sync/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TABLE, positions).

-record(pos, {
    key,                     %% {StrategyId, ConditionId, TokenId}
    shares       = 0.0,
    avg_price    = 0.0,
    realized_pnl = 0.0
}).

%% ---------------------------------------------------------------------------
%% Public API  (reads go directly to ETS)
%% ---------------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

-spec get_position(binary(), binary(), binary()) ->
    {ok, #{shares := float(), avg_price := float(),
           notional := float(), realized_pnl := float()}} | not_found.
get_position(StrategyId, ConditionId, TokenId) ->
    case ets:lookup(?TABLE, {StrategyId, ConditionId, TokenId}) of
        [R] -> {ok, pos_to_map(R)};
        []  -> not_found
    end.

-spec get_strategy_total(binary()) ->
    #{net_exposure := float(), gross_exposure := float(),
      realized_pnl := float(), unrealized_pnl := float()}.
get_strategy_total(StrategyId) ->
    Rows = [R || R <- ets:tab2list(?TABLE),
                 element(1, R#pos.key) =:= StrategyId],
    aggregate_rows(Rows).

-spec get_global_total() ->
    #{net_exposure := float(), gross_exposure := float(),
      realized_pnl := float(), unrealized_pnl := float()}.
get_global_total() ->
    aggregate_rows(ets:tab2list(?TABLE)).

%% Wipe all positions — for test use only.
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
    ?TABLE = ets:new(?TABLE, [named_table, set, public,
                               {keypos, #pos.key},
                               {read_concurrency, true},
                               {write_concurrency, true}]),
    ok = event_bus:subscribe(fill),
    {ok, #{}}.

handle_call(reset, _From, St) ->
    ets:delete_all_objects(?TABLE),
    {reply, ok, St};
handle_call(sync, _From, St) ->
    {reply, ok, St};
handle_call(_Req, _From, St) ->
    {reply, {error, unknown}, St}.

handle_cast(_Msg, St) ->
    {noreply, St}.

handle_info({event, fill, Fill}, St) ->
    apply_fill(Fill),
    {noreply, St};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) ->
    ok.

%% ---------------------------------------------------------------------------
%% Internal
%% ---------------------------------------------------------------------------

apply_fill(Fill) ->
    StrategyId  = maps:get(strategy_id,  Fill, <<>>),
    ConditionId = maps:get(condition_id, Fill, <<>>),
    TokenId     = maps:get(token_id,     Fill, <<>>),
    Side        = maps:get(side,         Fill, buy),
    Price       = maps:get(fill_price,   Fill, 0.0),
    Size        = maps:get(fill_size,    Fill, 0.0),
    Key = {StrategyId, ConditionId, TokenId},
    Existing = case ets:lookup(?TABLE, Key) of
        [R] -> R;
        []  -> #pos{key = Key}
    end,
    Updated = update_pos(Existing, Side, Price, Size),
    ets:insert(?TABLE, Updated).

update_pos(#pos{shares = OldShares, avg_price = AvgP, realized_pnl = RPnl} = Pos,
           buy, Price, Size) ->
    NewShares = OldShares + Size,
    NewAvg    = case NewShares > 0.0 of
        true  -> (OldShares * AvgP + Size * Price) / NewShares;
        false -> 0.0
    end,
    Pos#pos{shares = NewShares, avg_price = NewAvg, realized_pnl = RPnl};
update_pos(#pos{shares = OldShares, avg_price = AvgP, realized_pnl = RPnl} = Pos,
           sell, Price, Size) ->
    Closed    = min(Size, max(0.0, OldShares)),
    NewShares = OldShares - Size,
    NewRPnl   = RPnl + Closed * (Price - AvgP),
    Pos#pos{shares = NewShares, realized_pnl = NewRPnl}.

aggregate_rows(Rows) ->
    lists:foldl(fun(#pos{shares = S, avg_price = P, realized_pnl = R}, Acc) ->
        Notional = S * P,
        Acc#{
            net_exposure   => maps:get(net_exposure,   Acc) + Notional,
            gross_exposure => maps:get(gross_exposure,  Acc) + abs(Notional),
            realized_pnl   => maps:get(realized_pnl,   Acc) + R,
            unrealized_pnl => maps:get(unrealized_pnl, Acc)  %% needs live price, 0 for now
        }
    end, #{net_exposure => 0.0, gross_exposure => 0.0,
           realized_pnl => 0.0, unrealized_pnl => 0.0}, Rows).

pos_to_map(#pos{shares = S, avg_price = P, realized_pnl = R}) ->
    #{shares       => S,
      avg_price    => P,
      notional     => S * P,
      realized_pnl => R}.
