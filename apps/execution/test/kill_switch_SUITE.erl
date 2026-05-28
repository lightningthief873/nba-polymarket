-module(kill_switch_SUITE).

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([default_armed/1, disarm_halts/1, rearm_resumes/1, last_changed_updates/1]).

all() ->
    [default_armed, disarm_halts, rearm_resumes, last_changed_updates].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    kill_switch:arm(),
    ok.

init_per_testcase(_Name, Config) ->
    kill_switch:arm(),
    Config.

end_per_testcase(_Name, _Config) ->
    kill_switch:arm(),
    ok.

%% Default is armed (trading allowed).
default_armed(_Config) ->
    true = kill_switch:is_armed().

%% Disarming blocks trading.
disarm_halts(_Config) ->
    ok   = kill_switch:disarm(),
    false = kill_switch:is_armed().

%% Re-arming after disarm resumes trading.
rearm_resumes(_Config) ->
    kill_switch:disarm(),
    false = kill_switch:is_armed(),
    ok   = kill_switch:arm(),
    true = kill_switch:is_armed().

%% last_changed/0 timestamp advances monotonically on each state change.
last_changed_updates(_Config) ->
    kill_switch:arm(),
    T0 = kill_switch:last_changed(),
    kill_switch:disarm(),
    T1 = kill_switch:last_changed(),
    true = T1 > T0,
    kill_switch:arm(),
    T2 = kill_switch:last_changed(),
    true = T2 > T1.
