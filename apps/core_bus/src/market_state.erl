-module(market_state).
-behaviour(gen_server).

-export([start_link/0, start/0]).
-export([get_book/2, get_top/2, get_mid/2, get_all/2,
         subscribe_changes/2, all_rows/0, sync/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TABLE,      market_state).
-define(WINDOW_MAX, 1000).
-define(WINDOW_NS,  60_000_000_000).  %% 60 s in nanoseconds

-record(mrow, {
    key,
    bids             = [],
    asks             = [],
    best_bid         = 0.0,
    best_ask         = 1.0,
    mid              = 0.5,
    spread           = 1.0,
    last_trade_price = 0.0,
    last_trade_size  = 0.0,
    last_trade_ts_ns = 0,
    vol_60s          = 0.0,
    volatility_60s   = 0.0,
    window           = queue:new(),   %% queue of {ts_ns, mid, trade_size}
    update_count     = 0
}).

%% ---------------------------------------------------------------------------
%% Public API (reads go directly to ETS — no gen_server round-trip)
%% ---------------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

-spec get_book(binary(), binary()) -> {ok, map()} | not_found.
get_book(ConditionId, TokenId) ->
    case ets:lookup(?TABLE, {ConditionId, TokenId}) of
        [R] -> {ok, #{bids => R#mrow.bids, asks => R#mrow.asks}};
        []  -> not_found
    end.

-spec get_top(binary(), binary()) -> {ok, {float(), float()}} | not_found.
get_top(ConditionId, TokenId) ->
    case ets:lookup(?TABLE, {ConditionId, TokenId}) of
        [R] -> {ok, {R#mrow.best_bid, R#mrow.best_ask}};
        []  -> not_found
    end.

-spec get_mid(binary(), binary()) -> {ok, float()} | not_found.
get_mid(ConditionId, TokenId) ->
    case ets:lookup(?TABLE, {ConditionId, TokenId}) of
        [R] -> {ok, R#mrow.mid};
        []  -> not_found
    end.

-spec get_all(binary(), binary()) -> {ok, map()} | not_found.
get_all(ConditionId, TokenId) ->
    case ets:lookup(?TABLE, {ConditionId, TokenId}) of
        [R] -> {ok, row_to_map(R)};
        []  -> not_found
    end.

-spec subscribe_changes(binary(), binary()) -> ok.
subscribe_changes(ConditionId, TokenId) ->
    true = gproc:reg({p, l, {market_change, ConditionId, TokenId}}),
    ok.

-spec all_rows() -> [map()].
all_rows() ->
    [row_to_map(R) || R <- ets:tab2list(?TABLE)].

%% Flush the gen_server mailbox — use after publishing test events to ensure
%% all handle_info({event, market, _}) have been processed before reading ETS.
-spec sync() -> ok.
sync() ->
    gen_server:call(?MODULE, sync, 30_000).

%% ---------------------------------------------------------------------------
%% gen_server callbacks
%% ---------------------------------------------------------------------------

init([]) ->
    ets:new(?TABLE, [named_table, set, public,
                     {keypos, 2},
                     {read_concurrency, true},
                     {write_concurrency, true}]),
    ok = event_bus:subscribe(market),
    {ok, #{}}.

handle_call(sync, _From, State) ->
    {reply, ok, State};
handle_call(_Req, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({event, market, Event}, State) ->
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
    ConditionId = maps:get(condition_id, Event, <<>>),
    TokenId     = maps:get(token_id,     Event, <<>>),
    Key = {ConditionId, TokenId},

    Bids    = sort_levels(maps:get(bids, Event, []), descending),
    Asks    = sort_levels(maps:get(asks, Event, []), ascending),
    BestBid = best_price(Bids, 0.0),
    BestAsk = best_price(Asks, 1.0),
    Mid     = (BestBid + BestAsk) / 2.0,
    Spread  = BestAsk - BestBid,
    LTP     = maps:get(last_trade_price, Event, 0.0),
    LTS     = maps:get(last_trade_size,  Event, 0.0),
    LtsTsNs = ts_from_meta(Event, NowNs),

    Existing = case ets:lookup(?TABLE, Key) of
        [R] -> R;
        []  -> #mrow{key = Key}
    end,
    Win1   = advance_window(Existing#mrow.window, NowNs, Mid, LTS),
    Vol60s = compute_vol(Win1, NowNs),
    Volat  = compute_volatility(Win1, NowNs),

    Row = Existing#mrow{
        bids             = Bids,
        asks             = Asks,
        best_bid         = BestBid,
        best_ask         = BestAsk,
        mid              = Mid,
        spread           = Spread,
        last_trade_price = LTP,
        last_trade_size  = LTS,
        last_trade_ts_ns = LtsTsNs,
        vol_60s          = Vol60s,
        volatility_60s   = Volat,
        window           = Win1,
        update_count     = Existing#mrow.update_count + 1
    },
    ets:insert(?TABLE, Row),
    maybe_notify(ConditionId, TokenId, Row).

sort_levels(Levels, Dir) ->
    Pairs = [{maps:get(price, L, 0.0), maps:get(size, L, 0.0)} || L <- Levels],
    Cmp = case Dir of
        descending -> fun({P1, _}, {P2, _}) -> P1 >= P2 end;
        ascending  -> fun({P1, _}, {P2, _}) -> P1 =< P2 end
    end,
    lists:sort(Cmp, Pairs).

best_price([{P, _} | _], _Default) -> P;
best_price([],            Default)  -> Default.

ts_from_meta(Event, Fallback) ->
    case maps:find(meta, Event) of
        {ok, Meta} ->
            case maps:get(timestamp_ns, Meta, 0) of
                Ts when Ts > 0 -> Ts;
                _              -> Fallback
            end;
        error -> Fallback
    end.

advance_window(Win, NowNs, Mid, TradeSize) ->
    Win1 = queue:in({NowNs, Mid, TradeSize}, Win),
    Win2 = drop_old(Win1, NowNs - ?WINDOW_NS),
    cap_window(Win2, ?WINDOW_MAX).

drop_old(Win, Cutoff) ->
    case queue:peek(Win) of
        {value, {Ts, _, _}} when Ts < Cutoff -> drop_old(queue:drop(Win), Cutoff);
        _                                     -> Win
    end.

cap_window(Win, Max) ->
    case queue:len(Win) > Max of
        true  -> cap_window(queue:drop(Win), Max);
        false -> Win
    end.

compute_vol(Win, NowNs) ->
    Cutoff = NowNs - ?WINDOW_NS,
    lists:foldl(fun({Ts, _, Sz}, Acc) when Ts >= Cutoff -> Acc + Sz;
                   (_, Acc)                              -> Acc
                end, 0.0, queue:to_list(Win)).

compute_volatility(Win, NowNs) ->
    Cutoff = NowNs - ?WINDOW_NS,
    Mids = [M || {Ts, M, _} <- queue:to_list(Win), Ts >= Cutoff],
    std_dev(Mids).

std_dev([])  -> 0.0;
std_dev([_]) -> 0.0;
std_dev(Xs)  ->
    N    = length(Xs),
    Mean = lists:sum(Xs) / N,
    Var  = lists:sum([(X - Mean) * (X - Mean) || X <- Xs]) / N,
    math:sqrt(Var).

maybe_notify(ConditionId, TokenId, Row) ->
    PropKey = {p, l, {market_change, ConditionId, TokenId}},
    case gproc:lookup_pids(PropKey) of
        [] -> ok;
        _  -> gproc:send(PropKey, {market_change, ConditionId, TokenId, row_to_map(Row)})
    end.

row_to_map(#mrow{key = {CId, TId}} = R) ->
    #{condition_id      => CId,
      token_id          => TId,
      bids              => R#mrow.bids,
      asks              => R#mrow.asks,
      best_bid          => R#mrow.best_bid,
      best_ask          => R#mrow.best_ask,
      mid               => R#mrow.mid,
      spread            => R#mrow.spread,
      last_trade_price  => R#mrow.last_trade_price,
      last_trade_size   => R#mrow.last_trade_size,
      last_trade_ts_ns  => R#mrow.last_trade_ts_ns,
      vol_60s           => R#mrow.vol_60s,
      volatility_60s    => R#mrow.volatility_60s,
      update_count      => R#mrow.update_count}.
