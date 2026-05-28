# Current task

Last updated: 2026-05-28 (Day 5 complete)
Last commit: pending
Branch: phase1/day-5-strategy-behaviour

## Phase: 1
## Day: 5 (DONE — pending commit)

## What we are doing right now
Day 5 complete. All tests green. Ready to commit.

## Done this session
- apps/strategies/src/strategy_behaviour.erl: behaviour module with 5 callbacks:
  init/1, on_market_event/2, on_game_event/2, on_clock_tick/2, terminate/2
- apps/strategies/src/strategy_runtime.erl: gen_server wrapper; subscribes to
  market+game events; 100ms clock_tick via send_after; emits signals via
  event_bus:publish(signal, Sig#{strategy_id => SId}); ETS self-registration;
  exposes sync/1 and get_info/1 for tests
- apps/strategies/src/strategy_supervisor.erl: simple_one_for_one supervisor;
  creates strategy_registry ETS in init/1; API: add_strategy/3, remove_strategy/1,
  list_strategies/0, get_strategy_state/1; transient restart, intensity=10/period=60
- apps/strategies/src/strategies/always_buy_at_30c.erl: first strategy; emits
  BUY signal when best_ask <= 0.30 and time gap >= min_gap_ms (default 5s);
  accepts #{min_gap_ms => 0} in init args for deterministic tests
- apps/strategies/src/signal_aggregator.erl: gen_server; subscribes to signal
  events; logs each signal; exposes metrics/0 and sync/0
- apps/strategies/src/strategies_sup.erl: root supervisor wiring signal_aggregator
  (worker) and strategy_supervisor (supervisor) under one_for_one
- apps/strategies/src/strategies.app.src: added gproc dep, registered names
- apps/core_bus/src/inspect.erl: added strategies/0 via dynamic dispatch to
  strategy_supervisor:list_strategies/0 (avoids circular dep at compile time)
- Makefile: explicit --module list for rebar3 proper
- apps/strategies/test/strategy_supervisor_SUITE.erl: 3 CT tests —
  spawn_many_kill_one (50 instances, kill one, verify restart + others unchanged),
  hot_add_remove (add, signal fires, remove, no signal after), determinism
  (1000 events via runtime, two runs produce same count, with min_gap_ms=0)
- apps/strategies/test/strategy_behaviour_prop.erl: 2 PropEr properties —
  prop_deterministic_dispatch (same events → same signals every run),
  prop_state_isolation (two instances with same input produce identical output)

## Acceptance gate verified
- make test: 10/10 CT tests + PropEr 4/4 (including 2 new) + Python 4/4 + Rust passing
- spawn_many_kill_one: kill one of 50, supervisor restarts it, 49 others unchanged ✓
- hot_add_remove: signal fires after add, process gone after remove, no signal after ✓
- determinism: min_gap_ms=0, 500/1000 events qualify, both runs count=500 ✓
- PropEr 100/100 each for prop_deterministic_dispatch and prop_state_isolation ✓
- Manual: inspect:strategies() prints table, strategy_supervisor:list_strategies() works ✓

## Architecture notes
- Guardian process pattern in CT init_per_suite: supervisor:start_link only
  exists (no non-linking version), so we spawn a guardian process (not linked
  to CT runner) that calls start_link. Guardian stays alive between test cases.
- ETS strategy_registry owned by strategy_supervisor process; destroyed on
  supervisor exit; new strategies overwrite stale entries on restart (self-healing)
- Signals emitted by strategy_runtime via event_bus:publish(signal, Map) with
  strategy_id injected by the runtime (behaviour modules don't know their own ID)
- always_buy_at_30c accepts min_gap_ms => 0 in init args to disable the 5s
  rate-limit for deterministic tests; production default is 5000ms

## Next concrete step
Day 6: order_router + paper_executor + kill_switch
Branch: phase1/day-6-order-router

## Blockers
None.

## Known flakiness
- ingest_subscriber_SUITE zmq_throughput_latency: occasionally measures p50>2ms
  under full-suite load (scheduler contention in WSL2). Passes when run alone.
  Not caused by Day 5 code. Logged in known_issues.md.
