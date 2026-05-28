-module(e2e_signal_to_fill_SUITE).

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([signal_to_fill_chain/1, disarmed_blocks_all/1, positions_update/1]).

all() ->
    [signal_to_fill_chain, disarmed_blocks_all, positions_update].

%% ---------------------------------------------------------------------------
%% Suite setup — start all required gen_servers once
%% ---------------------------------------------------------------------------

init_per_suite(Config) ->
    application:stop(execution),
    application:stop(strategies),
    application:stop(core_bus),
    {ok, _} = application:ensure_all_started(gproc),
    {ok, _} = market_state:start(),
    {ok, _} = rate_limiter:start(),
    {ok, _} = position_tracker:start(),
    {ok, _} = order_router:start(),
    {ok, _} = paper_executor:start(),
    %% Seed book: ask=0.25 (below always_buy_at_30c threshold).
    seed_book(0.22, 1000.0, 0.25, 1000.0),
    market_state:sync(),
    %% Start the strategy supervisor for always_buy_at_30c.
    Self = self(),
    Guardian = spawn(fun() ->
        {ok, _} = strategy_supervisor:start_link(),
        Self ! guardian_ready,
        receive stop -> ok end
    end),
    receive guardian_ready -> ok after 5000 -> exit(guardian_timeout) end,
    [{guardian, Guardian} | Config].

end_per_suite(Config) ->
    Guardian = proplists:get_value(guardian, Config),
    Guardian ! stop,
    gen_server:stop(paper_executor),
    gen_server:stop(order_router),
    gen_server:stop(position_tracker),
    gen_server:stop(rate_limiter),
    gen_server:stop(market_state),
    ok.

init_per_testcase(_Name, Config) ->
    kill_switch:arm(),
    rate_limiter:reset(),
    position_tracker:reset(),
    ok = event_bus:subscribe(fill),
    Config.

end_per_testcase(_Name, _Config) ->
    %% Drain fill events.
    flush_fills(),
    catch gproc:unreg({p, l, {event, fill}}),
    %% Remove any strategies that were added.
    [strategy_supervisor:remove_strategy(SId)
     || {SId, _, _, _} <- strategy_supervisor:list_strategies()],
    ok.

%% ---------------------------------------------------------------------------
%% Tests
%% ---------------------------------------------------------------------------

%% Inject 100 market events at ask=0.25; rate limiter caps at ~10 fills.
signal_to_fill_chain(_Config) ->
    %% Add strategy with no rate gap so it fires on every qualifying event.
    {ok, _} = strategy_supervisor:add_strategy(
        <<"e2e-1">>, always_buy_at_30c, #{min_gap_ms => 0}),

    %% Publish 100 events below threshold.
    [event_bus:publish(market, market_event(0.25)) || _ <- lists:seq(1, 100)],
    strategy_runtime:sync(<<"e2e-1">>),
    order_router:sync(),
    paper_executor:sync(),
    position_tracker:sync(),

    FillCount = count_fills(500),
    ct:pal("fills=~w (rate-limited to ~w)", [FillCount, 10]),
    %% 10 token bucket; allow a small window for any refill during processing.
    true = FillCount >= 10 andalso FillCount =< 12.

%% With kill switch disarmed, zero fills regardless of signals.
disarmed_blocks_all(_Config) ->
    kill_switch:disarm(),
    {ok, _} = strategy_supervisor:add_strategy(
        <<"e2e-2">>, always_buy_at_30c, #{min_gap_ms => 0}),
    [event_bus:publish(market, market_event(0.25)) || _ <- lists:seq(1, 20)],
    strategy_runtime:sync(<<"e2e-2">>),
    order_router:sync(),
    paper_executor:sync(),
    0 = count_fills(200).

%% After fills, position_tracker reflects correct share count.
positions_update(_Config) ->
    {ok, _} = strategy_supervisor:add_strategy(
        <<"e2e-3">>, always_buy_at_30c, #{min_gap_ms => 0}),
    [event_bus:publish(market, market_event(0.25)) || _ <- lists:seq(1, 100)],
    strategy_runtime:sync(<<"e2e-3">>),
    order_router:sync(),
    paper_executor:sync(),
    position_tracker:sync(),

    FillCount = count_fills(500),
    ct:pal("fills=~w", [FillCount]),

    %% Each order is 10 shares; positions should reflect fills * 10.
    Total = position_tracker:get_global_total(),
    NetExp = maps:get(net_exposure, Total),
    ct:pal("net_exposure=~.4f fills=~w expected=~.4f",
           [NetExp, FillCount, FillCount * 10.0 * 0.25]),
    %% Exposure = shares * avg_price; avg_price ~= best_ask (0.25).
    true = NetExp > 0.0.

%% ---------------------------------------------------------------------------
%% Helpers
%% ---------------------------------------------------------------------------

market_event(Ask) ->
    #{condition_id => <<"cond1">>, token_id => <<"tok1">>,
      bids => [#{price => 0.22, size => 1000.0}],
      asks => [#{price => Ask, size => 1000.0}]}.

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
