# Current task

Last updated: 2026-05-27 (Day 3 complete)
Last commit: pending
Branch: phase1/day-3-zmq-wiring

## Phase: 1
## Day: 3 (DONE — pending PR merge)

## What we are doing right now
Day 3 complete. All tests green. PR to open.

## Done this session
- rebar.config: added chumak 1.5.0, gproc 1.2.0 deps; proper 1.4.0 in test profile
- apps/core_bus/src/event_bus.erl: gproc-backed pub/sub wrapper (subscribe/publish/metrics)
- apps/core_bus/src/ingest_subscriber.erl: gen_server SUB socket; spawns recv_loop, decodes protobuf
  frames, publishes via event_bus, maintains p50/p99 latency histogram
- apps/core_bus/src/core_bus_sup.erl: added ingest_subscriber as permanent child
- apps/core_bus/src/core_bus.app.src: gproc/chumak in applications, zmq_host/port env
- adapters/mock_publisher/publisher.py: Publisher class; builds MarketEvent protos at configurable rate
- adapters/mock_publisher/main.py: CLI (--rate, --duration, --seed, --bind)
- adapters/mock_publisher/tests/test_publisher.py: proto roundtrip + rate accuracy tests
- apps/core_bus/test/event_bus_prop.erl: PropEr 100-test pub/sub invariant
- apps/core_bus/test/ingest_subscriber_SUITE.erl: 11-second ZMQ throughput/latency CT test
- .github/workflows/ci.yml: pyzmq + pytest in pip install
- Makefile: mock-publish, ingest-shell targets; pytest in test target

## Bug fixed
- ingest_subscriber:init/1 used `spawn_link(fun() -> recv_loop(Socket, self()) end)` where
  `self()` evaluates in the SPAWNED process context (the recv_loop itself), so all
  gen_server:cast calls went to the wrong process. Fixed by capturing `Self = self()` before
  the spawn_link call.

## Acceptance gate verified
- make test: all pass
- CT: recv=10973, errors=0, p50=172µs, p99=580µs (all thresholds met)
- PropEr event_bus: 100/100 passed
- Python tests: 4/4 passed
- Rust tests: passing

## Next concrete step
Day 4: Event bus + market_state ETS table
Branch: phase1/day-4-market-state

## Blockers
None.

## Notes for next session
- chumak:socket(sub) without identity uses start_link NOT under chumak_sup — plain gen_server
- chumak:subscribe is gen_server:cast (async); process CAST before CALL ensures subscription
  is in topics list before peer_ready is triggered
- RECONNECT_TIMEOUT in chumak = 2000ms; start Python publisher BEFORE core_bus to avoid
  losing messages in the reconnect window
- BrokenPipeError at end of CT test is expected (publisher runs past port_close)
