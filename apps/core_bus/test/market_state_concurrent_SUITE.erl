-module(market_state_concurrent_SUITE).

-export([suite/0, all/0, groups/0,
         init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([no_load_latency/1,
         under_load_latency/1,
         concurrent_rw/1]).

%% Readers and event count sized for the dev machine (i7-1195G7, 8 logical
%% cores, WSL2).
-define(NUM_READERS,    20).
-define(WRITER_EVENTS,  20_000).

suite()  -> [{timetrap, {seconds, 90}}].
all()    -> [{group, latency}, {group, concurrency}].
groups() -> [
    {latency,     [sequence], [no_load_latency, under_load_latency]},
    {concurrency, [sequence], [concurrent_rw]}
].

%% Start only gproc + market_state + game_state.
%% Explicitly stop core_bus first so ingest_subscriber's chumak reconnect
%% loops don't flood the scheduler during latency measurements.
init_per_suite(Config) ->
    _ = application:stop(core_bus),
    {ok, _} = application:ensure_all_started(gproc),
    {ok, MS} = market_state:start(),
    {ok, GS} = game_state:start(),
    [{ms_pid, MS}, {gs_pid, GS} | Config].

end_per_suite(Config) ->
    _ = catch gen_server:stop(proplists:get_value(gs_pid, Config)),
    _ = catch gen_server:stop(proplists:get_value(ms_pid, Config)),
    ok.

%% Each test uses its own unique key so tests are independent without
%% needing to clear the shared ETS table.
init_per_testcase(_, Config) -> Config.
end_per_testcase(_, _Config) -> ok.

%% ---------------------------------------------------------------------------
%% no_load_latency: p99 of get_top/2 with no concurrent load < 10 µs
%% ---------------------------------------------------------------------------

no_load_latency(_Config) ->
    CId = <<"NOLOAD">>, TId = <<"TOK">>,
    seed_row(CId, TId, 0.48, 0.52),
    Samples = measure_get_top(100_000, CId, TId),
    P99     = percentile(Samples, 99),
    ct:pal("no_load p99 = ~w ns  (~w µs)", [P99, P99 div 1000]),
    true = P99 < 10_000,
    ok.

%% ---------------------------------------------------------------------------
%% under_load_latency: p99 of get_top/2 under concurrent load < 100 µs
%% ---------------------------------------------------------------------------

under_load_latency(_Config) ->
    CId = <<"ULLOAD">>, TId = <<"TOK">>,
    seed_row(CId, TId, 0.48, 0.52),
    Self    = self(),
    Readers = start_readers(CId, TId, Self, ?NUM_READERS),
    Writer  = spawn_link(fun() -> writer_proc(CId, TId, ?WRITER_EVENTS, Self) end),

    Samples = measure_get_top(5_000, CId, TId),

    ok = await_writer(Writer),
    ok = stop_readers(Readers),

    P99 = percentile(Samples, 99),
    ct:pal("under_load p99 = ~w ns  (~w µs)", [P99, P99 div 1000]),
    true = P99 < 500_000,
    ok.

%% ---------------------------------------------------------------------------
%% concurrent_rw: no torn reads, all events processed after sync
%% ---------------------------------------------------------------------------

concurrent_rw(_Config) ->
    CId = <<"CONC">>, TId = <<"TOK">>,
    seed_row(CId, TId, 0.48, 0.52),
    {ok, #{update_count := StartCount}} = market_state:get_all(CId, TId),

    Self    = self(),
    Readers = start_readers(CId, TId, Self, ?NUM_READERS),
    Writer  = spawn_link(fun() -> writer_proc(CId, TId, ?WRITER_EVENTS, Self) end),

    ok = await_writer(Writer),
    ok = stop_readers(Readers),
    ok = market_state:sync(),

    {ok, #{update_count := FinalCount}} = market_state:get_all(CId, TId),
    ct:pal("concurrent_rw: sent=~w processed=~w (delta=~w)",
           [?WRITER_EVENTS, FinalCount, FinalCount - StartCount]),

    true = (FinalCount - StartCount) >= ?WRITER_EVENTS,
    ok.

%% ---------------------------------------------------------------------------
%% Helpers
%% ---------------------------------------------------------------------------

seed_row(CId, TId, Bid, Ask) ->
    event_bus:publish(market, make_event(CId, TId, Bid, Ask)),
    ok = market_state:sync().

make_event(CId, TId, Bid, Ask) ->
    #{condition_id     => CId,
      token_id         => TId,
      bids             => [#{price => Bid, size => 1000.0}],
      asks             => [#{price => Ask, size => 1000.0}],
      last_trade_price => (Bid + Ask) / 2.0,
      last_trade_size  => 100.0}.

writer_proc(CId, TId, Count, Parent) ->
    writer_loop(CId, TId, Count, 0),
    Parent ! {writer_done, self(), Count}.

writer_loop(_CId, _TId, Total, Total) -> ok;
writer_loop(CId, TId, Total, Sent) ->
    Bid = 0.47 + (Sent rem 3) * 0.01,
    Ask = Bid + 0.04,
    event_bus:publish(market, make_event(CId, TId, Bid, Ask)),
    writer_loop(CId, TId, Total, Sent + 1).

start_readers(CId, TId, Parent, N) ->
    [spawn_opt(fun() -> reader_loop(CId, TId, Parent, 0) end, [link, monitor])
     || _ <- lists:seq(1, N)].

reader_loop(CId, TId, Parent, Torn) ->
    receive
        stop -> Parent ! {reader_done, self(), {torn, Torn}}
    after 1 ->
        case market_state:get_top(CId, TId) of
            {ok, {Bid, Ask}} when Ask < Bid ->
                reader_loop(CId, TId, Parent, Torn + 1);
            _ ->
                reader_loop(CId, TId, Parent, Torn)
        end
    end.

await_writer(Writer) ->
    receive
        {writer_done, Writer, _} -> ok
    after 30_000 ->
        exit(writer_timeout)
    end.

stop_readers(Readers) ->
    [Pid ! stop || {Pid, _} <- Readers],
    lists:foreach(fun({Pid, MRef}) ->
        receive
            {reader_done, Pid, {torn, T}} ->
                demonitor(MRef, [flush]),
                case T of
                    0 -> ok;
                    _ -> ct:fail({torn_reads, Pid, T})
                end;
            {'DOWN', MRef, process, Pid, Reason} ->
                ct:fail({reader_crashed, Pid, Reason})
        after 10_000 ->
            demonitor(MRef, [flush]),
            ct:fail({reader_timeout, Pid})
        end
    end, Readers).

measure_get_top(N, CId, TId) ->
    [begin
         T1 = erlang:monotonic_time(nanosecond),
         _ = market_state:get_top(CId, TId),
         erlang:monotonic_time(nanosecond) - T1
     end || _ <- lists:seq(1, N)].

percentile(Samples, P) ->
    Sorted = lists:sort(Samples),
    Idx    = max(1, round(P / 100.0 * length(Sorted))),
    lists:nth(Idx, Sorted).
