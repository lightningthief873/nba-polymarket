-module(rate_limiter_SUITE).

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([hammer_100_in_burst/1, wait_and_retry/1, reset_refills/1]).

all() ->
    [hammer_100_in_burst, wait_and_retry, reset_refills].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(gproc),
    {ok, _} = rate_limiter:start(),
    Config.

end_per_suite(_Config) ->
    gen_server:stop(rate_limiter),
    ok.

init_per_testcase(_Name, Config) ->
    rate_limiter:reset(),
    Config.

end_per_testcase(_Name, _Config) ->
    ok.

%% Burst of 100 requests in rapid succession: exactly 10 should succeed
%% (bucket starts full at 10; refill during the loop is negligible).
hammer_100_in_burst(_Config) ->
    Results  = [rate_limiter:check_and_consume() || _ <- lists:seq(1, 100)],
    OkCount  = length([R || R <- Results, R =:= ok]),
    ct:pal("ok=~w rejected=~w", [OkCount, 100 - OkCount]),
    %% Allow 10-12 to account for tiny clock drift during the tight loop.
    true = OkCount >= 10 andalso OkCount =< 12.

%% After draining the bucket, waiting 1 second refills ~10 tokens.
wait_and_retry(_Config) ->
    %% Drain bucket completely.
    [rate_limiter:check_and_consume() || _ <- lists:seq(1, 20)],
    {error, rate_limited} = rate_limiter:check_and_consume(),
    %% Wait for refill.
    timer:sleep(1050),
    Results = [rate_limiter:check_and_consume() || _ <- lists:seq(1, 15)],
    OkCount = length([R || R <- Results, R =:= ok]),
    ct:pal("after 1s refill, ok=~w", [OkCount]),
    true = OkCount >= 9 andalso OkCount =< 11.

%% reset/0 restores the bucket to full capacity immediately.
reset_refills(_Config) ->
    [rate_limiter:check_and_consume() || _ <- lists:seq(1, 20)],
    {error, rate_limited} = rate_limiter:check_and_consume(),
    ok = rate_limiter:reset(),
    ok = rate_limiter:check_and_consume().
