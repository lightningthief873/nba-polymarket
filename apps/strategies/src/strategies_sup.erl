-module(strategies_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 1, period => 5},
    Children = [
        #{id      => signal_aggregator,
          start   => {signal_aggregator, start_link, []},
          restart => permanent,
          type    => worker},
        #{id      => strategy_supervisor,
          start   => {strategy_supervisor, start_link, []},
          restart => permanent,
          type    => supervisor}
    ],
    {ok, {SupFlags, Children}}.
