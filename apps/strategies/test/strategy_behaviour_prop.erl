-module(strategy_behaviour_prop).
-include_lib("proper/include/proper.hrl").

-export([prop_deterministic_dispatch/0, prop_state_isolation/0]).

-define(MOD, always_buy_at_30c).

%% For any sequence of market events, replaying them twice from the same
%% initial state must produce identical signal lists.
prop_deterministic_dispatch() ->
    ?FORALL(Events, non_empty(list(market_event())),
        begin
            {ok, S0} = ?MOD:init(#{min_gap_ms => 0}),
            {Sigs1, _} = replay(Events, S0),
            {Sigs2, _} = replay(Events, S0),
            Sigs1 =:= Sigs2
        end).

%% Two strategy instances starting from identical state and processing the
%% same event sequence must emit identical signals — no global state leakage.
prop_state_isolation() ->
    ?FORALL(Events, non_empty(list(market_event())),
        begin
            {ok, Sa} = ?MOD:init(#{min_gap_ms => 0}),
            {ok, Sb} = ?MOD:init(#{min_gap_ms => 0}),
            {SigsA, _} = replay(Events, Sa),
            {SigsB, _} = replay(Events, Sb),
            SigsA =:= SigsB
        end).

%% ---------------------------------------------------------------------------
%% Generators
%% ---------------------------------------------------------------------------

market_event() ->
    ?LET({AskFrac, CId, TId},
         {float(0.0, 1.0), non_empty(binary()), non_empty(binary())},
         #{condition_id => CId,
           token_id     => TId,
           asks         => [#{price => AskFrac, size => 100.0}],
           bids         => [#{price => max(0.0, AskFrac - 0.02), size => 100.0}]}).

%% ---------------------------------------------------------------------------
%% Helpers
%% ---------------------------------------------------------------------------

replay(Events, InitState) ->
    lists:foldl(fun(E, {Acc, St}) ->
        {ok, Sigs, NewSt} = ?MOD:on_market_event(E, St),
        {Acc ++ Sigs, NewSt}
    end, {[], InitState}, Events).
