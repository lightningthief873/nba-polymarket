-module(inspect).
-export([dump/0, dump_market/0, dump_games/0, strategies/0,
         execution_status/0, positions/0, positions/1,
         open_orders/0, killswitch/1]).

%% Quick summary of all live state — call from rebar3 shell.

dump() ->
    dump_market(),
    dump_games().

dump_market() ->
    Rows = market_state:all_rows(),
    io:format("~n=== MARKET STATE (~w rows) ===~n", [length(Rows)]),
    io:format("~-24s ~-24s ~8s ~8s ~8s ~8s ~10s~n",
              ["ConditionId", "TokenId", "Bid", "Ask", "Mid", "Vol60s", "Updates"]),
    io:format("~s~n", [lists:duplicate(80, $-)]),
    lists:foreach(fun(R) ->
        io:format("~-24s ~-24s ~8.4f ~8.4f ~8.4f ~8.2f ~10w~n",
                  [trunc_bin(maps:get(condition_id, R), 24),
                   trunc_bin(maps:get(token_id,     R), 24),
                   maps:get(best_bid,     R),
                   maps:get(best_ask,     R),
                   maps:get(mid,          R),
                   maps:get(vol_60s,      R),
                   maps:get(update_count, R)])
    end, lists:sort(fun(A, B) ->
        maps:get(condition_id, A) =< maps:get(condition_id, B)
    end, Rows)).

dump_games() ->
    Games = game_state:all_games(),
    io:format("~n=== GAME STATE (~w rows) ===~n", [length(Games)]),
    io:format("~-16s ~-10s ~-10s ~6s ~6s ~4s ~9s ~5s ~10s~n",
              ["GameId", "Home", "Away", "H-Scr", "A-Scr", "Qtr", "Clock", "Late", "Updates"]),
    io:format("~s~n", [lists:duplicate(80, $-)]),
    lists:foreach(fun(G) ->
        LateStr = case maps:get(late_game_flag, G) of true -> "YES"; false -> "no" end,
        io:format("~-16s ~-10s ~-10s ~6w ~6w ~4w ~9w ~5s ~10w~n",
                  [trunc_bin(maps:get(game_id,       G), 16),
                   trunc_bin(maps:get(home_team,     G), 10),
                   trunc_bin(maps:get(away_team,     G), 10),
                   maps:get(home_score,    G),
                   maps:get(away_score,    G),
                   maps:get(period,        G),
                   maps:get(game_clock_ms, G),
                   LateStr,
                   maps:get(update_count,  G)])
    end, lists:sort(fun(A, B) ->
        maps:get(game_id, A) =< maps:get(game_id, B)
    end, Games)).

%% Dynamic dispatch avoids a compile-time circular dep (core_bus ← strategies).
strategies() ->
    case erlang:function_exported(strategy_supervisor, list_strategies, 0) of
        false ->
            io:format("strategies app not running~n");
        true ->
            Rows = strategy_supervisor:list_strategies(),
            io:format("~n=== STRATEGIES (~w running) ===~n", [length(Rows)]),
            io:format("~-24s ~-30s ~-14s ~s~n",
                      ["StrategyId", "Module", "Pid", "Status"]),
            io:format("~s~n", [lists:duplicate(80, $-)]),
            lists:foreach(fun({SId, Mod, Pid, Status}) ->
                io:format("~-24s ~-30w ~-14w ~w~n",
                          [trunc_bin(SId, 24), Mod, Pid, Status])
            end, lists:sort(fun({A,_,_,_},{B,_,_,_}) -> A =< B end, Rows))
    end.

%% ---------------------------------------------------------------------------
%% Execution commands (dynamic dispatch to avoid circular compile-time dep)
%% ---------------------------------------------------------------------------

execution_status() ->
    Armed = case erlang:function_exported(kill_switch, is_armed, 0) of
        true  -> kill_switch:is_armed();
        false -> unavailable
    end,
    Tokens = case erlang:function_exported(rate_limiter, tokens, 0) of
        true  -> rate_limiter:tokens();
        false -> unavailable
    end,
    OpenN = case erlang:function_exported(paper_executor, open_orders, 0) of
        true  -> length(paper_executor:open_orders());
        false -> unavailable
    end,
    RouterMetrics = case erlang:function_exported(order_router, metrics, 0) of
        true  -> order_router:metrics();
        false -> unavailable
    end,
    SwitchLabel = case Armed of true -> "armed"; false -> "DISARMED"; _ -> "unavailable" end,
    TokensStr   = case Tokens of unavailable -> "n/a"; T -> io_lib:format("~.2f", [T]) end,
    io:format("~n=== EXECUTION STATUS ===~n"),
    io:format("  Kill switch : ~s~n",   [SwitchLabel]),
    io:format("  Rate tokens : ~s~n",   [TokensStr]),
    io:format("  Open orders : ~w~n",   [OpenN]),
    io:format("  Router      : ~p~n",   [RouterMetrics]).

positions() ->
    case erlang:function_exported(position_tracker, get_global_total, 0) of
        false ->
            io:format("execution app not running~n");
        true  ->
            Global = position_tracker:get_global_total(),
            io:format("~n=== POSITIONS (global) ===~n"),
            io:format("  net_exposure   : ~.4f~n", [maps:get(net_exposure,   Global)]),
            io:format("  gross_exposure : ~.4f~n", [maps:get(gross_exposure,  Global)]),
            io:format("  realized_pnl   : ~.4f~n", [maps:get(realized_pnl,   Global)])
    end.

positions(StrategyId) ->
    case erlang:function_exported(position_tracker, get_strategy_total, 1) of
        false ->
            io:format("execution app not running~n");
        true  ->
            Total = position_tracker:get_strategy_total(StrategyId),
            io:format("~n=== POSITIONS strategy=~s ===~n", [StrategyId]),
            io:format("  net_exposure   : ~.4f~n", [maps:get(net_exposure,   Total)]),
            io:format("  gross_exposure : ~.4f~n", [maps:get(gross_exposure,  Total)]),
            io:format("  realized_pnl   : ~.4f~n", [maps:get(realized_pnl,   Total)])
    end.

open_orders() ->
    case erlang:function_exported(paper_executor, open_orders, 0) of
        false ->
            io:format("execution app not running~n");
        true  ->
            Orders = paper_executor:open_orders(),
            io:format("~n=== OPEN ORDERS (~w) ===~n", [length(Orders)]),
            io:format("~-36s ~-6s ~-6s ~6s ~8s ~10s~n",
                      ["OrderId", "Side", "Type", "Price", "Size", "StratId"]),
            io:format("~s~n", [lists:duplicate(80, $-)]),
            lists:foreach(fun(O) ->
                io:format("~-36s ~-6w ~-6w ~6.4f ~8.2f ~s~n",
                          [maps:get(order_id,    O),
                           maps:get(side,        O),
                           maps:get(order_type,  O),
                           maps:get(price,       O),
                           maps:get(size,        O),
                           trunc_bin(maps:get(strategy_id, O, <<>>), 10)])
            end, Orders)
    end.

killswitch(on) ->
    case erlang:function_exported(kill_switch, arm, 0) of
        true  -> kill_switch:arm(),   io:format("kill switch: ARMED (trading allowed)~n");
        false -> io:format("execution app not running~n")
    end;
killswitch(off) ->
    case erlang:function_exported(kill_switch, disarm, 0) of
        true  -> kill_switch:disarm(), io:format("kill switch: DISARMED (all orders halted)~n");
        false -> io:format("execution app not running~n")
    end.

%% ---------------------------------------------------------------------------

trunc_bin(B, Max) when is_binary(B), byte_size(B) =< Max ->
    binary_to_list(B);
trunc_bin(B, Max) when is_binary(B) ->
    binary_to_list(binary:part(B, 0, Max));
trunc_bin(X, _) ->
    lists:flatten(io_lib:format("~p", [X])).
