-module(paper_executor).
-behaviour(gen_server).

-export([start_link/0, start/0]).
-export([open_orders/0, fill_count/0, sync/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(OPEN_ORDERS, open_orders).

-record(st, {fill_count = 0}).

%% ---------------------------------------------------------------------------
%% Public API
%% ---------------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

-spec open_orders() -> [map()].
open_orders() ->
    [Order || {_Id, Order} <- ets:tab2list(?OPEN_ORDERS)].

-spec fill_count() -> non_neg_integer().
fill_count() ->
    gen_server:call(?MODULE, fill_count).

-spec sync() -> ok.
sync() ->
    gen_server:call(?MODULE, sync).

%% ---------------------------------------------------------------------------
%% gen_server callbacks
%% ---------------------------------------------------------------------------

init([]) ->
    ?OPEN_ORDERS = ets:new(?OPEN_ORDERS, [named_table, set, public,
                                           {keypos, 1},
                                           {read_concurrency, true}]),
    ok = event_bus:subscribe(order),
    ok = event_bus:subscribe(market),
    {ok, #st{}}.

handle_call(fill_count, _From, St) ->
    {reply, St#st.fill_count, St};
handle_call(sync, _From, St) ->
    {reply, ok, St};
handle_call(_Req, _From, St) ->
    {reply, {error, unknown}, St}.

handle_cast(_Msg, St) ->
    {noreply, St}.

handle_info({event, order, Order}, St) ->
    {noreply, process_order(Order, St)};
handle_info({event, market, Event}, St) ->
    ConditionId = maps:get(condition_id, Event, <<>>),
    TokenId     = maps:get(token_id,     Event, <<>>),
    %% Build book directly from the event to avoid a race with market_state ETS:
    %% both this process and market_state receive the same event asynchronously;
    %% querying market_state:get_book here could return stale data.
    Book = event_to_book(Event),
    {noreply, reevaluate_open({ConditionId, TokenId}, Book, St)};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) ->
    ok.

%% ---------------------------------------------------------------------------
%% Internal
%% ---------------------------------------------------------------------------

process_order(Order, St) ->
    ConditionId = maps:get(condition_id, Order, <<>>),
    TokenId     = maps:get(token_id,     Order, <<>>),
    OrderType   = maps:get(order_type,   Order, gtc),
    case market_state:get_book(ConditionId, TokenId) of
        not_found ->
            case OrderType of
                gtc -> ets:insert(?OPEN_ORDERS, {maps:get(order_id, Order), Order});
                _   -> logger:info("[paper_executor] no book, ~w rejected", [OrderType])
            end,
            St;
        {ok, Book} ->
            try_fill(Order, Book, St)
    end.

try_fill(Order, Book, St) ->
    Side      = maps:get(side,       Order, buy),
    OrderType = maps:get(order_type, Order, gtc),
    Price     = maps:get(price,      Order, 0.0),
    Size      = maps:get(size,       Order, 0.0),
    case {Side, OrderType} of
        {buy, gtc} ->
            case best_ask(Book) of
                {BestAsk, _} when Price >= BestAsk, BestAsk > 0.0 ->
                    emit_fill(Order, BestAsk, Size, St#st{fill_count = St#st.fill_count + 1});
                _ ->
                    ets:insert(?OPEN_ORDERS, {maps:get(order_id, Order), Order}),
                    St
            end;
        {sell, gtc} ->
            case best_bid(Book) of
                {BestBid, _} when Price =< BestBid, BestBid > 0.0 ->
                    emit_fill(Order, BestBid, Size, St#st{fill_count = St#st.fill_count + 1});
                _ ->
                    ets:insert(?OPEN_ORDERS, {maps:get(order_id, Order), Order}),
                    St
            end;
        {buy, fok} ->
            case best_ask(Book) of
                {BestAsk, AskSize} when Price >= BestAsk, AskSize >= Size ->
                    emit_fill(Order, BestAsk, Size, St#st{fill_count = St#st.fill_count + 1});
                _ ->
                    logger:info("[paper_executor] FOK buy rejected, no liquidity"),
                    St
            end;
        {sell, fok} ->
            case best_bid(Book) of
                {BestBid, BidSize} when Price =< BestBid, BidSize >= Size ->
                    emit_fill(Order, BestBid, Size, St#st{fill_count = St#st.fill_count + 1});
                _ ->
                    logger:info("[paper_executor] FOK sell rejected, no liquidity"),
                    St
            end;
        {buy, ioc} ->
            case best_ask(Book) of
                {BestAsk, AskSize} when Price >= BestAsk ->
                    FillSize = min(Size, AskSize),
                    emit_fill(Order, BestAsk, FillSize, St#st{fill_count = St#st.fill_count + 1});
                _ ->
                    logger:info("[paper_executor] IOC buy rejected, price too low"),
                    St
            end;
        {sell, ioc} ->
            case best_bid(Book) of
                {BestBid, BidSize} when Price =< BestBid ->
                    FillSize = min(Size, BidSize),
                    emit_fill(Order, BestBid, FillSize, St#st{fill_count = St#st.fill_count + 1});
                _ ->
                    logger:info("[paper_executor] IOC sell rejected, price too high"),
                    St
            end
    end.

emit_fill(Order, FillPrice, FillSize, St) ->
    Fill = #{
        fill_id      => <<"fill-", (maps:get(order_id, Order))/binary>>,
        order_id     => maps:get(order_id,     Order),
        strategy_id  => maps:get(strategy_id,  Order, <<>>),
        condition_id => maps:get(condition_id, Order, <<>>),
        token_id     => maps:get(token_id,     Order, <<>>),
        side         => maps:get(side,         Order, buy),
        fill_price   => FillPrice,
        fill_size    => FillSize,
        timestamp_ns => erlang:system_time(nanosecond)
    },
    ets:delete(?OPEN_ORDERS, maps:get(order_id, Order)),
    event_bus:publish(fill, Fill),
    logger:info("[paper_executor] fill ~p @ ~.4f x ~.2f",
                [maps:get(order_id, Fill), FillPrice, FillSize]),
    St.

reevaluate_open({ConditionId, TokenId}, Book, St) ->
    Candidates = [Order || {_Id, Order} <- ets:tab2list(?OPEN_ORDERS),
                            maps:get(condition_id, Order, <<>>) =:= ConditionId,
                            maps:get(token_id,     Order, <<>>) =:= TokenId],
    lists:foldl(fun(Order, AccSt) ->
        ets:delete(?OPEN_ORDERS, maps:get(order_id, Order)),
        try_fill(Order, Book, AccSt)
    end, St, Candidates).

event_to_book(Event) ->
    ToLevel = fun(L) -> {maps:get(price, L, 0.0), maps:get(size, L, 0.0)} end,
    Asks = lists:sort(fun({P1,_},{P2,_}) -> P1 =< P2 end,
                      [ToLevel(L) || L <- maps:get(asks, Event, [])]),
    Bids = lists:sort(fun({P1,_},{P2,_}) -> P1 >= P2 end,
                      [ToLevel(L) || L <- maps:get(bids, Event, [])]),
    #{asks => Asks, bids => Bids}.

best_ask(#{asks := [{P, S} | _]}) -> {P, S};
best_ask(_)                        -> {1.0, 0.0}.

best_bid(#{bids := [{P, S} | _]}) -> {P, S};
best_bid(_)                        -> {0.0, 0.0}.
