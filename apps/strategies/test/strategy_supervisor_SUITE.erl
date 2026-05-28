-module(strategy_supervisor_SUITE).

-export([suite/0, all/0, groups/0,
         init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([spawn_many_kill_one/1,
         hot_add_remove/1,
         determinism/1]).

-define(REGISTRY, strategy_registry).

suite()  -> [{timetrap, {seconds, 60}}].
all()    -> [{group, supervisor_tests}, {group, strategy_tests}].
groups() -> [
    {supervisor_tests, [sequence], [spawn_many_kill_one]},
    {strategy_tests,   [sequence], [hot_add_remove, determinism]}
].

%% ---------------------------------------------------------------------------
%% Suite setup/teardown
%%
%% strategy_supervisor is a supervisor — supervisor:start_link always links
%% to the calling process.  If we called it from init_per_suite directly, the
%% gen_server parent mechanism would kill it when the CT runner exits.
%%
%% Fix: spawn a long-lived Guardian process that calls start_link and keeps
%% the supervisor alive until end_per_suite tells it to stop.
%% ---------------------------------------------------------------------------

init_per_suite(Config) ->
    _ = application:stop(core_bus),
    {ok, _} = application:ensure_all_started(gproc),
    Self = self(),
    Guardian = spawn(fun() ->
        {ok, _} = strategy_supervisor:start_link(),
        Self ! guardian_ready,
        receive stop -> ok end
    end),
    receive
        guardian_ready -> ok
    after 5000 ->
        exit(guardian_timeout)
    end,
    [{guardian, Guardian} | Config].

end_per_suite(Config) ->
    Guardian = proplists:get_value(guardian, Config),
    Guardian ! stop,
    timer:sleep(100),
    ok.

%% Reset ETS between tests to prevent interference.
init_per_testcase(_, Config) ->
    lists:foreach(fun({SId, _, _}) ->
        catch strategy_supervisor:remove_strategy(SId)
    end, ets:tab2list(?REGISTRY)),
    Config.

end_per_testcase(_, _Config) ->
    lists:foreach(fun({SId, _, _}) ->
        catch strategy_supervisor:remove_strategy(SId)
    end, ets:tab2list(?REGISTRY)),
    ok.

%% ---------------------------------------------------------------------------
%% spawn_many_kill_one
%% Start 50 strategies, kill one, assert supervisor restarts it with a new Pid,
%% assert the remaining 49 Pids are unchanged.
%% ---------------------------------------------------------------------------

spawn_many_kill_one(_Config) ->
    Ids = [iolist_to_binary(io_lib:format("s~w", [N])) || N <- lists:seq(1, 50)],
    [{ok, _} = strategy_supervisor:add_strategy(Id, always_buy_at_30c, #{})
     || Id <- Ids],

    %% Capture all Pids before the kill.
    PidsBefore = maps:from_list(
        [{Id, pid_of(Id)} || Id <- Ids]),

    TargetId = <<"s1">>,
    OldPid   = maps:get(TargetId, PidsBefore),
    MRef     = monitor(process, OldPid),
    exit(OldPid, kill),

    %% Wait for old process to be confirmed dead.
    receive {'DOWN', MRef, process, OldPid, _} -> ok
    after 2000 -> ct:fail(kill_not_confirmed) end,

    %% Wait for supervisor to restart s1 with a new Pid.
    NewPid = wait_for_new_pid(TargetId, OldPid, 2000),
    ct:pal("s1 restarted: old=~w new=~w", [OldPid, NewPid]),
    true = is_process_alive(NewPid),

    %% All other 49 strategies must be unchanged.
    lists:foreach(fun(Id) ->
        Expected = maps:get(Id, PidsBefore),
        Expected = pid_of(Id),
        true     = is_process_alive(Expected)
    end, Ids -- [TargetId]),
    ok.

%% ---------------------------------------------------------------------------
%% hot_add_remove
%% Add a strategy, verify it emits a signal on a qualifying event, remove it,
%% verify no signal on the same event after removal.
%% ---------------------------------------------------------------------------

hot_add_remove(_Config) ->
    CId = <<"HC1">>, TId = <<"HT1">>,
    ok = event_bus:subscribe(signal),

    %% Add strategy with min_gap_ms=0 so every qualifying event fires.
    {ok, _} = strategy_supervisor:add_strategy(
                  <<"hot1">>, always_buy_at_30c, #{min_gap_ms => 0}),

    %% Inject ask=0.25 — below the 30c threshold.
    event_bus:publish(market, make_event(CId, TId, 0.24, 0.25)),

    receive
        {event, signal, Sig} ->
            'SIGNAL_ACTION_BUY' = maps:get(action, Sig),
            <<"hot1">>          = maps:get(strategy_id, Sig),
            ct:pal("hot_add_remove: signal received ~p", [Sig])
    after 1000 ->
        ct:fail(no_signal_after_add)
    end,

    %% Save Pid, then remove.
    [{_, _, StratPid}] = ets:lookup(?REGISTRY, <<"hot1">>),
    ok = strategy_supervisor:remove_strategy(<<"hot1">>),
    false = is_process_alive(StratPid),

    %% Drain any residual signals from the mailbox.
    flush_signals(),

    %% Same event again — no signal expected.
    event_bus:publish(market, make_event(CId, TId, 0.24, 0.25)),
    receive
        {event, signal, _} -> ct:fail(unexpected_signal_after_remove)
    after 200 ->
        ok
    end.

%% ---------------------------------------------------------------------------
%% determinism
%% Replay a fixed 1000-event sequence through always_buy_at_30c twice (via the
%% strategy_runtime) and assert identical signal counts.
%% ---------------------------------------------------------------------------

determinism(_Config) ->
    CId = <<"DC1">>, TId = <<"DT1">>,
    Events = det_events(1000, CId, TId),

    ok = event_bus:subscribe(signal),

    Count1 = run_det(<<"det1">>, Events),
    Count2 = run_det(<<"det2">>, Events),

    ct:pal("determinism: count1=~w count2=~w", [Count1, Count2]),
    true  = Count1 > 0,
    Count1 = Count2,
    ok.

%% ---------------------------------------------------------------------------
%% Helpers
%% ---------------------------------------------------------------------------

run_det(Id, Events) ->
    {ok, _} = strategy_supervisor:add_strategy(Id, always_buy_at_30c,
                                                #{min_gap_ms => 0}),
    [event_bus:publish(market, E) || E <- Events],
    ok = strategy_runtime:sync(Id),
    Count = drain_signal_count(),
    ok = strategy_supervisor:remove_strategy(Id),
    Count.

%% Count all {event, signal, _} messages already in the mailbox (after sync).
drain_signal_count() ->
    receive
        {event, signal, _} -> 1 + drain_signal_count()
    after 0 -> 0
    end.

flush_signals() ->
    receive {event, signal, _} -> flush_signals()
    after 0 -> ok
    end.

%% 1000 events alternating ask=0.25 and ask=0.55; half below threshold.
det_events(N, CId, TId) ->
    [make_event(CId, TId,
                0.24 + (I rem 2) * 0.30,
                0.25 + (I rem 2) * 0.30)
     || I <- lists:seq(1, N)].

make_event(CId, TId, Bid, Ask) ->
    #{condition_id => CId,
      token_id     => TId,
      bids         => [#{price => Bid, size => 1000.0}],
      asks         => [#{price => Ask, size => 1000.0}]}.

pid_of(StrategyId) ->
    [{_, _, Pid}] = ets:lookup(?REGISTRY, StrategyId),
    Pid.

wait_for_new_pid(Id, OldPid, Timeout) ->
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    wait_new_loop(Id, OldPid, Deadline).

wait_new_loop(Id, OldPid, Deadline) ->
    case ets:lookup(?REGISTRY, Id) of
        [{_, _, Pid}] when Pid =/= OldPid -> Pid;
        _ ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true  -> timer:sleep(10), wait_new_loop(Id, OldPid, Deadline);
                false -> ct:fail({restart_timeout, Id})
            end
    end.
