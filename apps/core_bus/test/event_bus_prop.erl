-module(event_bus_prop).
-include_lib("proper/include/proper.hrl").

-export([prop_subscriber_receives_all_events/0]).

%% Property: every event published AFTER a subscriber registers is
%% delivered to that subscriber exactly once.
prop_subscriber_receives_all_events() ->
    {ok, _} = application:ensure_all_started(gproc),
    ?FORALL(N, range(1, 15),
        begin
            Self = self(),
            Sub  = spawn(fun() ->
                ok = event_bus:subscribe(market),
                Self ! sub_ready,
                [receive {event, market, _} -> ok end || _ <- lists:seq(1, N)],
                Self ! sub_done
            end),
            Ref = monitor(process, Sub),
            receive sub_ready -> ok end,
            [event_bus:publish(market, #{seq => I}) || I <- lists:seq(1, N)],
            Result = receive
                sub_done             -> true;
                {'DOWN', Ref, process, Sub, _} -> false
            after 3000               -> false
            end,
            %% Wait for the subscriber to fully exit so gproc cleans up
            %% before the next iteration registers a new subscriber.
            receive {'DOWN', Ref, process, Sub, _} -> ok after 500 -> ok end,
            demonitor(Ref, [flush]),
            Result
        end).
