-module(paper_executor_SUITE).

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([gtc_buy_fills_immediately/1, gtc_buy_stays_open/1,
         gtc_open_fills_on_market_update/1, fok_fill/1, fok_reject/1,
         ioc_partial/1]).

all() ->
    [gtc_buy_fills_immediately, gtc_buy_stays_open,
     gtc_open_fills_on_market_update, fok_fill, fok_reject, ioc_partial].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(gproc),
    {ok, _} = market_state:start(),
    {ok, _} = position_tracker:start(),
    {ok, _} = paper_executor:start(),
    %% Seed book: ask=0.25/500, bid=0.22/400.
    seed_book(0.22, 400.0, 0.25, 500.0),
    market_state:sync(),
    Config.

end_per_suite(_Config) ->
    gen_server:stop(paper_executor),
    gen_server:stop(position_tracker),
    gen_server:stop(market_state),
    ok.

init_per_testcase(_Name, Config) ->
    %% Reset book to known state so tests don't bleed into each other.
    seed_book(0.22, 400.0, 0.25, 500.0),
    market_state:sync(),
    paper_executor:sync(),   %% drain any queued market events from the reset
    ok = event_bus:subscribe(fill),
    position_tracker:reset(),
    Config.

end_per_testcase(_Name, _Config) ->
    flush_fills(),
    gproc:unreg({p, l, {event, fill}}),
    ok.

%% GTC BUY with price >= best_ask fills immediately.
gtc_buy_fills_immediately(_Config) ->
    event_bus:publish(order, make_order(buy, 0.30, 10.0, gtc)),
    paper_executor:sync(),
    Fill = receive {event, fill, F} -> F after 500 -> ct:fail(no_fill) end,
    buy   = maps:get(side,       Fill),
    0.25  = maps:get(fill_price, Fill),
    10.0  = maps:get(fill_size,  Fill).

%% GTC BUY with price < best_ask stays in open_orders.
gtc_buy_stays_open(_Config) ->
    Order = make_order(buy, 0.20, 10.0, gtc),
    event_bus:publish(order, Order),
    paper_executor:sync(),
    0 = count_fills(50),
    Orders = paper_executor:open_orders(),
    true = length(Orders) >= 1.

%% An open GTC order fills when the market moves in our favour.
gtc_open_fills_on_market_update(_Config) ->
    Order = make_order(buy, 0.21, 10.0, gtc),
    event_bus:publish(order, Order),
    paper_executor:sync(),
    0 = count_fills(50),
    %% Now move the ask down to 0.20 — order price (0.21) >= new ask (0.20).
    seed_book(0.18, 400.0, 0.20, 500.0),
    paper_executor:sync(),
    Fill = receive {event, fill, F} -> F after 500 -> ct:fail(no_fill_after_update) end,
    0.20 = maps:get(fill_price, Fill),
    %% Restore original book for subsequent tests.
    seed_book(0.22, 400.0, 0.25, 500.0),
    paper_executor:sync().

%% FOK fills when price and size are both satisfied.
fok_fill(_Config) ->
    event_bus:publish(order, make_order(buy, 0.30, 10.0, fok)),
    paper_executor:sync(),
    Fill = receive {event, fill, F} -> F after 500 -> ct:fail(no_fill) end,
    0.25 = maps:get(fill_price, Fill).

%% FOK is rejected when requested size exceeds available liquidity.
fok_reject(_Config) ->
    event_bus:publish(order, make_order(buy, 0.30, 99999.0, fok)),
    paper_executor:sync(),
    0 = count_fills(100).

%% IOC fills only the available size.
ioc_partial(_Config) ->
    event_bus:publish(order, make_order(buy, 0.30, 99999.0, ioc)),
    paper_executor:sync(),
    Fill = receive {event, fill, F} -> F after 500 -> ct:fail(no_fill) end,
    FillSize = maps:get(fill_size, Fill),
    %% Should have filled 500.0 (available ask size), not 99999.0.
    true = FillSize =< 500.0,
    true = FillSize > 0.0.

%% ---------------------------------------------------------------------------
%% Helpers
%% ---------------------------------------------------------------------------

make_order(Side, Price, Size, Type) ->
    #{order_id     => <<"ord-test-", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
      strategy_id  => <<"test-strategy">>,
      condition_id => <<"cond1">>,
      token_id     => <<"tok1">>,
      side         => Side,
      price        => Price,
      size         => Size,
      order_type   => Type,
      timestamp_ns => erlang:system_time(nanosecond)}.

seed_book(Bid, BidSz, Ask, AskSz) ->
    event_bus:publish(market, #{
        condition_id => <<"cond1">>, token_id => <<"tok1">>,
        bids => [#{price => Bid, size => BidSz}],
        asks => [#{price => Ask, size => AskSz}]
    }).

count_fills(TimeoutMs) ->
    count_fills(TimeoutMs, 0).
count_fills(TimeoutMs, N) ->
    receive {event, fill, _} -> count_fills(TimeoutMs, N + 1)
    after TimeoutMs -> N
    end.

flush_fills() ->
    receive {event, fill, _} -> flush_fills()
    after 0 -> ok
    end.
