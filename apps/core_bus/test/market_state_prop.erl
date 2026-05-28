-module(market_state_prop).
-include_lib("proper/include/proper.hrl").

-export([prop_state_matches_naive_replay/0]).

%% ---------------------------------------------------------------------------
%% Generators
%% ---------------------------------------------------------------------------

condition_id() -> oneof([<<"COND_A">>, <<"COND_B">>, <<"COND_C">>]).
token_id()     -> oneof([<<"TOK_1">>, <<"TOK_2">>]).

price_level() ->
    ?LET({P, S},
         {float(0.01, 0.99), float(100.0, 10000.0)},
         #{price => P, size => S}).

market_event_gen() ->
    ?LET({CId, TId, Bids, Asks, LTP, LTS},
         {condition_id(), token_id(),
          list(price_level()), list(price_level()),
          float(0.01, 0.99), float(100.0, 10000.0)},
         #{condition_id     => CId,
           token_id         => TId,
           bids             => Bids,
           asks             => Asks,
           last_trade_price => LTP,
           last_trade_size  => LTS}).

%% ---------------------------------------------------------------------------
%% Property
%%
%% After replaying N events through market_state, the ETS rows for each
%% (condition_id, token_id) key must match a pure-functional naive replay:
%%   - update_count   = number of events for that key
%%   - best_bid       = max bid price from last event (or 0.0 if no bids)
%%   - best_ask       = min ask price from last event (or 1.0 if no asks)
%%   - mid            = (best_bid + best_ask) / 2
%% ---------------------------------------------------------------------------

prop_state_matches_naive_replay() ->
    {ok, _} = application:ensure_all_started(gproc),
    {ok, _} = ensure_market_state(),
    ?FORALL(Events, non_empty(list(market_event_gen())),
        begin
            %% Reset state so counts are fresh for this iteration.
            ets:delete_all_objects(market_state),
            Expected = naive_replay(Events),
            [event_bus:publish(market, E) || E <- Events],
            ok = market_state:sync(),
            verify_all_keys(Expected)
        end).

%% ---------------------------------------------------------------------------
%% Helpers
%% ---------------------------------------------------------------------------

ensure_market_state() ->
    case whereis(market_state) of
        undefined -> market_state:start_link();
        Pid       -> {ok, Pid}
    end.

%% Pure-functional replay: track {best_bid, best_ask, mid, count} per key.
naive_replay(Events) ->
    lists:foldl(fun naive_apply/2, #{}, Events).

naive_apply(Event, Acc) ->
    CId = maps:get(condition_id, Event),
    TId = maps:get(token_id, Event),
    Key = {CId, TId},

    Bids = sort_desc(maps:get(bids, Event, [])),
    Asks = sort_asc(maps:get(asks, Event, [])),
    BestBid = best(Bids, 0.0),
    BestAsk = best(Asks, 1.0),
    Mid     = (BestBid + BestAsk) / 2.0,
    Prev    = maps:get(Key, Acc, #{count => 0}),

    maps:put(Key, #{best_bid  => BestBid,
                    best_ask  => BestAsk,
                    mid       => Mid,
                    count     => maps:get(count, Prev) + 1},
             Acc).

sort_desc(Ls) ->
    lists:sort(fun(#{price := P1}, #{price := P2}) -> P1 >= P2 end, Ls).

sort_asc(Ls) ->
    lists:sort(fun(#{price := P1}, #{price := P2}) -> P1 =< P2 end, Ls).

best([#{price := P} | _], _) -> P;
best([],                  D) -> D.

verify_all_keys(Expected) ->
    maps:fold(fun({CId, TId}, NRow, Acc) ->
        case market_state:get_all(CId, TId) of
            {ok, ERow} ->
                Acc andalso
                    maps:get(update_count, ERow) =:= maps:get(count, NRow) andalso
                    abs(maps:get(best_bid, ERow) - maps:get(best_bid, NRow)) < 1.0e-9 andalso
                    abs(maps:get(best_ask, ERow) - maps:get(best_ask, NRow)) < 1.0e-9 andalso
                    abs(maps:get(mid,      ERow) - maps:get(mid,      NRow)) < 1.0e-9;
            not_found ->
                false
        end
    end, true, Expected).
