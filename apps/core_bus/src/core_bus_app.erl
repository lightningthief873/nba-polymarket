-module(core_bus_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    core_bus_sup:start_link().

stop(_State) ->
    ok.
