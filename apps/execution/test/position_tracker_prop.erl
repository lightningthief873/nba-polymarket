-module(position_tracker_prop).
-include_lib("proper/include/proper.hrl").

-export([prop_buy_shares_accumulate/0, prop_sell_reduces_shares/0,
         prop_realized_pnl_on_sell/0]).

%% ---------------------------------------------------------------------------
%% Generators
%% ---------------------------------------------------------------------------

pos_price() -> float(0.01, 0.99).
pos_size()  -> float(1.0, 100.0).

fill(Side) ->
    ?LET({Price, Size}, {pos_price(), pos_size()},
         #{strategy_id  => <<"prop-strat">>,
           condition_id => <<"prop-cond">>,
           token_id     => <<"prop-tok">>,
           side         => Side,
           fill_price   => Price,
           fill_size    => Size}).

%% ---------------------------------------------------------------------------
%% Properties
%% ---------------------------------------------------------------------------

%% After N buy fills the total shares == sum(fill_sizes).
prop_buy_shares_accumulate() ->
    ?FORALL(Fills, non_empty(list(fill(buy))),
        begin
            Tracker = start_fresh_tracker(),
            lists:foreach(fun(F) -> apply_fill_direct(F) end, Fills),
            position_tracker:sync(),
            {ok, Pos} = position_tracker:get_position(
                <<"prop-strat">>, <<"prop-cond">>, <<"prop-tok">>),
            TotalShares = lists:foldl(fun(F, Acc) ->
                Acc + maps:get(fill_size, F)
            end, 0.0, Fills),
            stop_tracker(Tracker),
            abs(maps:get(shares, Pos) - TotalShares) < 0.001
        end).

%% Selling everything bought results in zero shares and non-negative realized PnL
%% (for a sell above avg buy price) or non-positive (below).
prop_sell_reduces_shares() ->
    ?FORALL({BuyPrice, BuySize, SellPrice},
            {pos_price(), pos_size(), pos_price()},
        begin
            Tracker = start_fresh_tracker(),
            BuyFill  = #{strategy_id  => <<"prop-strat">>,
                         condition_id => <<"prop-cond">>,
                         token_id     => <<"prop-tok">>,
                         side  => buy,  fill_price => BuyPrice,  fill_size => BuySize},
            SellFill = #{strategy_id  => <<"prop-strat">>,
                         condition_id => <<"prop-cond">>,
                         token_id     => <<"prop-tok">>,
                         side  => sell, fill_price => SellPrice, fill_size => BuySize},
            apply_fill_direct(BuyFill),
            apply_fill_direct(SellFill),
            position_tracker:sync(),
            {ok, Pos} = position_tracker:get_position(
                <<"prop-strat">>, <<"prop-cond">>, <<"prop-tok">>),
            ExpectedPnl = BuySize * (SellPrice - BuyPrice),
            ActualPnl   = maps:get(realized_pnl, Pos),
            Shares      = maps:get(shares, Pos),
            stop_tracker(Tracker),
            abs(Shares) < 0.001 andalso abs(ActualPnl - ExpectedPnl) < 0.001
        end).

%% Realized PnL = sum over sells of (sell_price - avg_buy_price) * size.
prop_realized_pnl_on_sell() ->
    ?FORALL({BuyPrice, SellPrice, Size},
            {pos_price(), pos_price(), pos_size()},
        begin
            Tracker = start_fresh_tracker(),
            apply_fill_direct(#{strategy_id  => <<"pnl-strat">>,
                                condition_id => <<"pnl-cond">>,
                                token_id     => <<"pnl-tok">>,
                                side => buy,  fill_price => BuyPrice,  fill_size => Size}),
            apply_fill_direct(#{strategy_id  => <<"pnl-strat">>,
                                condition_id => <<"pnl-cond">>,
                                token_id     => <<"pnl-tok">>,
                                side => sell, fill_price => SellPrice, fill_size => Size}),
            position_tracker:sync(),
            {ok, Pos} = position_tracker:get_position(
                <<"pnl-strat">>, <<"pnl-cond">>, <<"pnl-tok">>),
            Expected = Size * (SellPrice - BuyPrice),
            Actual   = maps:get(realized_pnl, Pos),
            stop_tracker(Tracker),
            abs(Actual - Expected) < 0.001
        end).

%% ---------------------------------------------------------------------------
%% Internal helpers
%% ---------------------------------------------------------------------------

start_fresh_tracker() ->
    case whereis(position_tracker) of
        undefined ->
            application:ensure_all_started(gproc),
            {ok, Pid} = position_tracker:start(),
            Pid;
        Pid ->
            position_tracker:reset(),
            Pid
    end.

stop_tracker(Pid) ->
    case process_info(Pid, registered_name) of
        {registered_name, position_tracker} ->
            gen_server:stop(position_tracker);
        _ ->
            ok
    end.

%% Publish a fill event directly so position_tracker's handle_info fires.
apply_fill_direct(Fill) ->
    event_bus:publish(fill, Fill).
