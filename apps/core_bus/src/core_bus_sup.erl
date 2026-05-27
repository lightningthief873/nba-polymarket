-module(core_bus_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 30},
    Children = [
        #{id      => ingest_subscriber,
          start   => {ingest_subscriber, start_link, []},
          restart => permanent,
          type    => worker}
    ],
    {ok, {SupFlags, Children}}.
