-module(ingest_subscriber).
-behaviour(gen_server).

-export([start_link/0, metrics/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(MAX_LATENCY_SAMPLES, 10_000).

-record(state, {
    socket          :: pid(),
    recv_pid        :: pid(),
    recv_count  = 0 :: non_neg_integer(),
    error_count = 0 :: non_neg_integer(),
    latency_us  = [] :: [non_neg_integer()]
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec metrics() -> map().
metrics() ->
    gen_server:call(?MODULE, metrics).

%% ---------------------------------------------------------------------------
%% gen_server callbacks
%% ---------------------------------------------------------------------------

init([]) ->
    Host = application:get_env(core_bus, zmq_host, "127.0.0.1"),
    Port = application:get_env(core_bus, zmq_port, 5555),
    {ok, Socket} = chumak:socket(sub),
    ok = chumak:subscribe(Socket, <<>>),
    {ok, _ConnPid} = chumak:connect(Socket, tcp, Host, Port),
    Self = self(),
    RecvPid = spawn_link(fun() -> recv_loop(Socket, Self) end),
    {ok, #state{socket = Socket, recv_pid = RecvPid}}.

handle_cast({zmq_recv, _RecvTs, Frames}, State) when length(Frames) =/= 2 ->
    {noreply, State#state{error_count = State#state.error_count + 1}};

handle_cast({zmq_recv, RecvTs, [Topic, Payload]}, State) ->
    case decode(Topic, Payload) of
        {ok, EventType, Event} ->
            LatUs = latency_us(RecvTs, Event),
            event_bus:publish(EventType, Event),
            Lats = bounded_prepend(LatUs, State#state.latency_us, ?MAX_LATENCY_SAMPLES),
            {noreply, State#state{
                recv_count  = State#state.recv_count + 1,
                latency_us  = Lats
            }};
        error ->
            {noreply, State#state{error_count = State#state.error_count + 1}}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_call(metrics, _From, State) ->
    {reply, compute_metrics(State), State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown}, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{recv_pid = RecvPid}) ->
    exit(RecvPid, shutdown),
    ok.

%% ---------------------------------------------------------------------------
%% Internal
%% ---------------------------------------------------------------------------

recv_loop(Socket, Parent) ->
    case chumak:recv_multipart(Socket) of
        {ok, Frames} ->
            RecvTs = erlang:system_time(nanosecond),
            gen_server:cast(Parent, {zmq_recv, RecvTs, Frames}),
            recv_loop(Socket, Parent);
        {error, _Reason} ->
            exit(zmq_recv_error)
    end.

decode(<<"market.", _/binary>>, Payload) ->
    try
        Event = market_pb:decode_msg(Payload, market_event),
        {ok, market, Event}
    catch _:_ -> error
    end;
decode(<<"game.", _/binary>>, Payload) ->
    try
        Event = game_pb:decode_msg(Payload, game_event),
        {ok, game, Event}
    catch _:_ -> error
    end;
decode(_Topic, _Payload) ->
    error.

latency_us(RecvNs, Event) ->
    SentNs = case maps:find(meta, Event) of
        {ok, #{timestamp_ns := Ts}} when Ts > 0 -> Ts;
        _ -> RecvNs
    end,
    max(0, (RecvNs - SentNs) div 1000).

bounded_prepend(Val, List, Max) when length(List) < Max ->
    [Val | List];
bounded_prepend(Val, [_ | Rest], _Max) ->
    [Val | Rest].

compute_metrics(#state{recv_count  = C,
                        error_count = E,
                        latency_us  = Lats}) ->
    #{recv_count  => C,
      error_count => E,
      p50_us      => percentile(Lats, 50),
      p99_us      => percentile(Lats, 99)}.

percentile([], _P) -> 0;
percentile(Samples, P) ->
    Sorted = lists:sort(Samples),
    N      = length(Sorted),
    Idx    = max(1, round(P / 100.0 * N)),
    lists:nth(Idx, Sorted).
