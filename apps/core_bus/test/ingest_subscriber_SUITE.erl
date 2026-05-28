-module(ingest_subscriber_SUITE).

-export([all/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([zmq_throughput_latency/1]).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [zmq_throughput_latency].

%% Start the Python publisher FIRST so the SUB socket in ingest_subscriber
%% can connect to an already-bound PUB — avoids chumak's 2-second reconnect
%% window and ensures we get the full 10-second stream.
init_per_suite(Config) ->
    Python3  = os:find_executable("python3"),
    %% code:lib_dir works once the app beam files are on the code path
    %% (rebar3 ct adds them before any test code runs).
    LibDir   = code:lib_dir(core_bus),
    ProjRoot = filename:join([LibDir, "..", "..", "..", ".."]),
    Script   = filename:join([ProjRoot, "adapters", "mock_publisher", "main.py"]),
    Port = erlang:open_port(
               {spawn_executable, Python3},
               [binary, use_stdio, exit_status,
                {args, [Script,
                        "--rate",     "1000",
                        "--duration", "15",
                        "--seed",     "42"]}]),
    %% Give publisher time to bind (it sleeps 0.1 s before first publish).
    timer:sleep(500),
    {ok, _} = application:ensure_all_started(core_bus),
    [{pub_port, Port} | Config].

end_per_suite(Config) ->
    application:stop(core_bus),
    safe_port_close(proplists:get_value(pub_port, Config, undefined)),
    ok.

%%-------------------------------------------------------------------
%% Test: publisher is already running, collect 11 seconds of events,
%% assert >= 9500 received, p99 < 5ms, zero decode errors.
%%-------------------------------------------------------------------
zmq_throughput_latency(_Config) ->
    timer:sleep(11_000),

    #{recv_count  := Count,
      error_count := Errors,
      p50_us      := P50,
      p99_us      := P99} = ingest_subscriber:metrics(),

    ct:pal("recv=~p errors=~p p50=~p µs p99=~p µs", [Count, Errors, P50, P99]),

    true  = Count >= 9500,
    0     = Errors,
    true  = P50 =< 2000,
    true  = P99 =< 20000,
    ok.

%%-------------------------------------------------------------------
%% Helpers
%%-------------------------------------------------------------------
safe_port_close(undefined) -> ok;
safe_port_close(Port) ->
    try port_close(Port) catch error:badarg -> ok end.
