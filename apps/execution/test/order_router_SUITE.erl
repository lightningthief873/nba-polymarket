-module(order_router_SUITE).

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([accepts_valid_signal/1, kill_switch_blocks/1,
         rate_limit_respected/1, risk_size_rejected/1]).

all() ->
    [accepts_valid_signal, kill_switch_blocks,
     rate_limit_respected, risk_size_rejected].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(gproc),
    {ok, _} = market_state:start(),
    {ok, _} = rate_limiter:start(),
    {ok, _} = position_tracker:start(),
    {ok, _} = order_router:start(),
    %% Seed a known book.
    event_bus:publish(market, #{
        condition_id => <<"cond1">>, token_id => <<"tok1">>,
        bids => [#{price => 0.22, size => 500.0}],
        asks => [#{price => 0.25, size => 500.0}]
    }),
    market_state:sync(),
    Config.

end_per_suite(_Config) ->
    gen_server:stop(order_router),
    gen_server:stop(position_tracker),
    gen_server:stop(rate_limiter),
    gen_server:stop(market_state),
    ok.

init_per_testcase(_Name, Config) ->
    kill_switch:arm(),
    rate_limiter:reset(),
    position_tracker:reset(),
    ok = event_bus:subscribe(order),
    Config.

end_per_testcase(_Name, _Config) ->
    %% Drain any leftover order events.
    flush_orders(),
    gproc:unreg({p, l, {event, order}}),
    ok.

%% A valid signal below threshold produces one order event.
accepts_valid_signal(_Config) ->
    Signal = make_signal(0.25, 10.0),
    event_bus:publish(signal, Signal),
    order_router:sync(),
    Order = receive {event, order, O} -> O after 500 -> ct:fail(no_order) end,
    <<"cond1">> = maps:get(condition_id, Order),
    buy         = maps:get(side,        Order),
    10.0        = maps:get(size,        Order),
    gtc         = maps:get(order_type,  Order).

%% With kill switch disarmed, no orders should be produced.
kill_switch_blocks(_Config) ->
    kill_switch:disarm(),
    [event_bus:publish(signal, make_signal(0.25, 10.0)) || _ <- lists:seq(1, 5)],
    order_router:sync(),
    0 = count_orders(100),
    #{rejected := R} = order_router:metrics(),
    true = R >= 5.

%% Rate limiter caps at 10 per burst; excess signals are dropped.
rate_limit_respected(_Config) ->
    [event_bus:publish(signal, make_signal(0.25, 10.0)) || _ <- lists:seq(1, 30)],
    order_router:sync(),
    Count = count_orders(200),
    ct:pal("orders emitted=~w (expected ~w)", [Count, 10]),
    true = Count >= 10 andalso Count =< 12.

%% A signal with size below min_order_size (5.0) should be rejected.
risk_size_rejected(_Config) ->
    %% Config default min_order_size = 5.0; send size = 1.0.
    event_bus:publish(signal, make_signal(0.25, 1.0)),
    order_router:sync(),
    0 = count_orders(100).

%% ---------------------------------------------------------------------------
%% Helpers
%% ---------------------------------------------------------------------------

make_signal(Price, Size) ->
    #{action       => 'SIGNAL_ACTION_BUY',
      strategy_id  => <<"test-strategy">>,
      condition_id => <<"cond1">>,
      token_id     => <<"tok1">>,
      target_price => Price,
      size         => Size,
      confidence   => 0.5,
      reason       => "test"}.

count_orders(TimeoutMs) ->
    count_orders(TimeoutMs, 0).
count_orders(TimeoutMs, N) ->
    receive
        {event, order, _} -> count_orders(TimeoutMs, N + 1)
    after TimeoutMs -> N
    end.

flush_orders() ->
    receive {event, order, _} -> flush_orders()
    after 0 -> ok
    end.
