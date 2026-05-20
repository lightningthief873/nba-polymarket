-module(hello_nif_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0, groups/0]).
-export([hello_returns_expected_binary/1, hello_10k_under_100ms/1]).

all() ->
    [{group, basic}].

groups() ->
    [{basic, [sequence], [hello_returns_expected_binary, hello_10k_under_100ms]}].

hello_returns_expected_binary(_Config) ->
    <<"hello from rust">> = hello_nif:hello(),
    ok.

hello_10k_under_100ms(_Config) ->
    Start = erlang:monotonic_time(millisecond),
    [hello_nif:hello() || _ <- lists:seq(1, 10000)],
    Elapsed = erlang:monotonic_time(millisecond) - Start,
    ct:pal("10 000 NIF calls in ~p ms", [Elapsed]),
    true = (Elapsed < 100),
    ok.
