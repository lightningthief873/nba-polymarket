-module(risk_check).

%% Pure module — no process. Called by order_router with pre-fetched context.

-export([check/3]).

-type reason() :: min_order_size
                | position_per_token_exceeded
                | position_per_strategy_exceeded
                | global_exposure_exceeded.

-spec check(Signal :: map(), Context :: map(), Config :: map()) ->
    ok | {reject, reason()}.
check(Signal, Context, Config) ->
    Size = maps:get(size, Signal, 0.0),
    MinSize = maps:get(min_order_size, Config, 5.0),
    if
        Size < MinSize ->
            {reject, min_order_size};
        true ->
            MaxPerToken = maps:get(max_position_per_token, Config, 100.0),
            CurrShares  = maps:get(token_shares, Context, 0.0),
            if
                CurrShares + Size > MaxPerToken ->
                    {reject, position_per_token_exceeded};
                true ->
                    MaxPerStrat   = maps:get(max_position_per_strategy, Config, 500.0),
                    StratExposure = maps:get(strategy_net_exposure, Context, 0.0),
                    Price         = maps:get(target_price, Signal, 0.5),
                    if
                        StratExposure + Size * Price > MaxPerStrat ->
                            {reject, position_per_strategy_exceeded};
                        true ->
                            MaxGlobal      = maps:get(max_global_exposure, Config, 1000.0),
                            GlobalExposure = maps:get(global_net_exposure, Context, 0.0),
                            if
                                GlobalExposure + Size * Price > MaxGlobal ->
                                    {reject, global_exposure_exceeded};
                                true ->
                                    ok
                            end
                    end
            end
    end.
