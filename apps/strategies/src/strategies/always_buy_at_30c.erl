-module(always_buy_at_30c).
-behaviour(strategy_behaviour).

-export([init/1, on_market_event/2, on_game_event/2, on_clock_tick/2, terminate/2]).

-define(DEFAULT_MIN_GAP_MS, 5_000).
-define(THRESHOLD,          0.30).

%% ---------------------------------------------------------------------------
%% strategy_behaviour callbacks
%% ---------------------------------------------------------------------------

init(Args) ->
    Gap = maps:get(min_gap_ms, Args, ?DEFAULT_MIN_GAP_MS),
    {ok, #{seen_count => 0, last_signal_ts => 0, min_gap_ms => Gap}}.

on_market_event(Event, #{last_signal_ts := LastTs, min_gap_ms := Gap} = State) ->
    BestAsk = get_best_ask(Event),
    NowMs   = erlang:system_time(millisecond),
    NewState = State#{seen_count => maps:get(seen_count, State) + 1},
    case BestAsk =< ?THRESHOLD andalso (NowMs - LastTs) >= Gap of
        true ->
            Signal = #{action       => 'SIGNAL_ACTION_BUY',
                       condition_id => maps:get(condition_id, Event, <<>>),
                       token_id     => maps:get(token_id,     Event, <<>>),
                       target_price => BestAsk,
                       size         => 10.0,
                       confidence   => 0.5,
                       reason       => "ask under 30c"},
            {ok, [Signal], NewState#{last_signal_ts => NowMs}};
        false ->
            {ok, [], NewState}
    end.

on_game_event(_Event, State) ->
    {ok, [], State}.

on_clock_tick(_NowNs, State) ->
    {ok, [], State}.

terminate(_Reason, _State) ->
    ok.

%% ---------------------------------------------------------------------------
%% Internal
%% ---------------------------------------------------------------------------

%% Handle raw events (asks = [#{price,size}]) and processed events (asks =
%% [{Price, Size}] tuples from market_state), falling back to a best_ask key.
get_best_ask(Event) ->
    Asks = maps:get(asks, Event, []),
    Prices = [case A of
                  #{price := P} -> P;
                  {P, _}        -> P;
                  _             -> 1.0
              end || A <- Asks],
    case Prices of
        []  -> maps:get(best_ask, Event, 1.0);
        Ps  -> lists:min(Ps)
    end.
