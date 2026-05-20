-module(hello_nif).
-export([hello/0]).
-on_load(init/0).

-define(APPNAME, core_bus).
-define(LIBNAME, hello_nif).

init() ->
    SoName = case code:priv_dir(?APPNAME) of
        {error, bad_name} ->
            %% Fallback for running outside a rebar3 release (e.g. bare erl).
            case filelib:is_dir(filename:join(["..", priv])) of
                true  -> filename:join(["..", priv, ?LIBNAME]);
                false -> filename:join([priv, ?LIBNAME])
            end;
        Dir ->
            filename:join(Dir, ?LIBNAME)
    end,
    erlang:load_nif(SoName, 0).

hello() ->
    erlang:nif_error(nif_not_loaded).
