#!/usr/bin/env escript
%% Compile all proto files in proto/nba_polymarket/v1/ using gpb.
%% Run from the project root after `rebar3 compile` has fetched gpb.
main([]) ->
    %% Load gpb from the rebar3 build tree.
    Deps = filelib:wildcard("_build/default/lib/*/ebin"),
    lists:foreach(fun code:add_path/1, Deps),
    code:add_path("_build/default/plugins/gpb/ebin"),

    ProtoDir   = "proto/nba_polymarket/v1",
    OutErlDir  = "apps/core_bus/src/generated",
    OutHrlDir  = "apps/core_bus/include/generated",

    ok = filelib:ensure_dir(OutErlDir ++ "/."),
    ok = filelib:ensure_dir(OutHrlDir ++ "/."),

    Opts = [
        {i, ProtoDir},
        {i, "proto"},
        {module_name_suffix, "_pb"},
        {o_erl, OutErlDir},
        {o_hrl, OutHrlDir},
        maps,
        {maps_unset_optional, omitted},
        type_specs,
        {rename, {msg_name, snake_case}}
    ],

    ProtoFiles = lists:sort(filelib:wildcard(ProtoDir ++ "/*.proto")),
    case ProtoFiles of
        [] ->
            io:format("ERROR: no .proto files found in ~s~n", [ProtoDir]),
            halt(1);
        _ ->
            ok
    end,

    lists:foreach(
        fun(File) ->
            io:format("  gpb: ~s~n", [File]),
            case gpb_compile:file(File, Opts) of
                ok ->
                    ok;
                {error, Reason} ->
                    io:format("ERROR compiling ~s:~n  ~p~n", [File, Reason]),
                    halt(1)
            end
        end,
        ProtoFiles
    ),
    io:format("Erlang protobuf codegen complete.~n").
