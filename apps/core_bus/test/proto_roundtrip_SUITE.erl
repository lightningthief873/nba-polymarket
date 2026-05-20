-module(proto_roundtrip_SUITE).
-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([erlang_python_rust_round_trip/1]).

all() -> [erlang_python_rust_round_trip].

erlang_python_rust_round_trip(Config) ->
    Event = #{
        meta => #{
            timestamp_ns => 1700000000000000000,
            ingested_ns  => 1700000000000001000,
            source       => 'SOURCE_POLYMARKET_WS',
            trace_id     => <<"test-trace-001">>
        },
        condition_id     => <<"0xABCD">>,
        token_id         => <<"0x1234">>,
        bids => [#{price => 0.55, size => 100.0}],
        asks => [#{price => 0.56, size =>  80.0}],
        last_trade_price => 0.555,
        last_trade_size  => 50.0
    },
    ErlBytes = market_pb:encode_msg(Event, market_event),

    TmpFile = filename:join(?config(priv_dir, Config), "market_event.bin"),
    ok = file:write_file(TmpFile, ErlBytes),

    %% Navigate from _build/test/lib/core_bus up four levels to the project root.
    LibDir   = code:lib_dir(core_bus),
    ProjRoot = filename:join([LibDir, "..", "..", "..", ".."]),

    Python3  = os:find_executable("python3"),
    PyScript = filename:join([ProjRoot, "adapters", "proto", "roundtrip.py"]),
    {ok, PyBytes} = run_exe(Python3, [PyScript, TmpFile]),

    RustBin = filename:join([ProjRoot, "nifs", "proto_codec",
                             "target", "debug", "proto_roundtrip"]),
    {ok, RustBytes} = run_exe(RustBin, [TmpFile]),

    ErlBytes = PyBytes,
    ErlBytes = RustBytes,
    ct:pal("round-trip OK: ~p bytes (Erlang = Python = Rust)", [byte_size(ErlBytes)]).

run_exe(Exe, Args) ->
    Port = erlang:open_port(
               {spawn_executable, Exe},
               [binary, exit_status, {args, Args}]),
    collect_port(Port, <<>>).

collect_port(Port, Acc) ->
    receive
        {Port, {data, D}}        -> collect_port(Port, <<Acc/binary, D/binary>>);
        {Port, {exit_status, 0}} -> {ok, Acc};
        {Port, {exit_status, N}} ->
            ct:fail("subprocess exited ~p, output so far: ~p", [N, Acc])
    end.
