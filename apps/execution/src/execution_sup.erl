-module(execution_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 3, period => 10},
    Children = [
        #{id      => rate_limiter,
          start   => {rate_limiter, start_link, []},
          restart => permanent,
          type    => worker},
        #{id      => position_tracker,
          start   => {position_tracker, start_link, []},
          restart => permanent,
          type    => worker},
        #{id      => order_router,
          start   => {order_router, start_link, []},
          restart => permanent,
          type    => worker},
        #{id      => paper_executor,
          start   => {paper_executor, start_link, []},
          restart => permanent,
          type    => worker}
    ],
    {ok, {SupFlags, Children}}.
