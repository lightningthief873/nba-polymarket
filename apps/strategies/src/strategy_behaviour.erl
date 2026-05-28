-module(strategy_behaviour).

%% Each strategy is a module implementing these callbacks.
%% The strategy_runtime gen_server owns process lifecycle and routing;
%% the behaviour module provides pure(ish) event-handling logic.

-callback init(Args :: term()) ->
    {ok, State :: term()} | {stop, Reason :: term()}.

-callback on_market_event(Event :: map(), State :: term()) ->
    {ok, Signals :: [map()], NewState :: term()} |
    {stop, Reason :: term(), NewState :: term()}.

-callback on_game_event(Event :: map(), State :: term()) ->
    {ok, Signals :: [map()], NewState :: term()}.

-callback on_clock_tick(NowNs :: integer(), State :: term()) ->
    {ok, Signals :: [map()], NewState :: term()}.

-callback terminate(Reason :: term(), State :: term()) -> ok.
