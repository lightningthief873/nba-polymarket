# Current task

Last updated: 2026-05-28 (Day 6 complete)
Last commit: 9d50f97
Branch: phase1/day-6-router-executor-killswitch

## Phase: 1
## Day: 6 (DONE — ready to merge)

## What we are doing right now
Day 6 complete. All tests green. Ready to PR + merge.

## Done this session
- apps/execution/src/kill_switch.erl: persistent_term flag; is_armed/0
  sub-microsecond read; arm/0, disarm/0 log every change at warning level
- apps/execution/src/rate_limiter.erl: gen_server token bucket; 10 tokens/sec,
  burst 10; continuous refill via monotonic time; reset/0 for tests
- apps/execution/src/position_tracker.erl: gen_server + ETS; subscribes to fill
  events; updates shares/avg_price/realized_pnl; direct ETS reads for get_position;
  get_strategy_total/1 and get_global_total/0 via ETS scan; reset/0
- apps/execution/src/risk_check.erl: pure module; check(Signal, Context, Config);
  guards: min_order_size, per-token cap, per-strategy notional cap, global exposure
- apps/execution/src/order_router.erl: gen_server subscribing to signal events;
  pipeline: kill_switch -> rate_limiter -> position fetch -> risk_check ->
  UUID v7 order -> publish order event; metrics/0 and sync/0
- apps/execution/src/paper_executor.erl: gen_server subscribing to order + market
  events; GTC/FOK/IOC fill semantics; open GTC orders park in ETS, re-evaluated
  on market events; book extracted directly from event (avoids ETS race with
  market_state); emits fill events consumed by position_tracker
- apps/execution/src/execution_sup.erl: one_for_one with 4 workers
- apps/execution/src/execution.app.src: added crypto, gproc, core_bus deps
- config/sys.config: Phase 1 risk defaults
- bin/cli: escript connecting to named node via RPC for shell-less control
- apps/core_bus/src/inspect.erl: execution_status/0, positions/0, positions/1,
  open_orders/0, killswitch/1 via dynamic dispatch
- rebar.config: ct_opts now points to config/sys.config
- Makefile: position_tracker_prop added to proper --module list
- Test suites: kill_switch_SUITE (4), rate_limiter_SUITE (3), order_router_SUITE
  (4), paper_executor_SUITE (6), position_tracker_prop (3×100), e2e_signal_to_fill
  (3) — all green

## Acceptance gate verified
- make test: all CT + PropEr pass (only pre-existing ZMQ flakiness)
- kill_switch: default armed, disarm/rearm, last_changed monotonic ✓
- rate_limiter: 100 in burst → exactly 10 succeed; 1s wait → 10 more ✓
- order_router: signals flow through, kill switch blocks, rate limit caps,
  risk rejects undersized orders ✓
- paper_executor: GTC immediate fill, GTC open/reeval, FOK fill/reject,
  IOC partial ✓
- position_tracker PropEr: buy accumulate, sell reduces shares, PnL identity ✓
- e2e: 100 events → ~10 fills (rate limited), kill switch blocks all,
  positions.net_exposure > 0 after fills ✓

## Architecture notes
- kill_switch uses persistent_term: is_armed() is just a map lookup, zero
  gen_server overhead on the signal hot path
- paper_executor reevaluate_open extracts book from the market event directly
  (not from market_state ETS) to avoid race: both gen_servers receive the same
  market event asynchronously and ETS may not be updated yet when paper_executor
  handles its copy
- UUID v7 generated inline in order_router using crypto:strong_rand_bytes;
  no extra dependency

## Next concrete step
Day 7: QuestDB + Redis + persistence layer
Branch: phase1/day-7-persistence

## Blockers
None.

## Known flakiness
- ingest_subscriber_SUITE zmq_throughput_latency: WSL2 scheduler starvation
  under full suite load. Documented in known_issues.md. Not Day 6 code.
