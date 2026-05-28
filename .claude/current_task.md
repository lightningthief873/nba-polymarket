# Current task

Last updated: 2026-05-28 (Day 4 complete)
Last commit: pending
Branch: phase1/day-4-market-state

## Phase: 1
## Day: 4 (DONE — pending commit)

## What we are doing right now
Day 4 complete. All tests green. Ready to commit.

## Done this session
- apps/core_bus/src/market_state.erl: gen_server with ETS backing (named_table, public,
  read_concurrency+write_concurrency); API: get_book/2, get_top/2, get_mid/2, get_all/2,
  subscribe_changes/2, all_rows/0, sync/0 (30s timeout); 60s rolling window for vol + volatility
- apps/core_bus/src/game_state.erl: gen_server with ETS backing; tracks score_diff,
  time_remaining_ms, late_game_flag (Q4 ≤ 2min), update_count; API: get_game/1,
  get_clock/1, get_score/1, all_games/0, sync/0
- apps/core_bus/src/inspect.erl: shell helper — inspect:dump/0, dump_market/0, dump_games/0
- apps/core_bus/src/core_bus_sup.erl: added market_state + game_state as permanent children
  (before ingest_subscriber in start order)
- apps/core_bus/src/core_bus.app.src: market_state, game_state added to registered
- apps/core_bus/test/market_state_prop.erl: PropEr 100-test property — naive replay matches
  ETS state for best_bid, best_ask, mid, update_count
- apps/core_bus/test/market_state_concurrent_SUITE.erl: CT suite with 3 tests:
  no_load_latency (p99 < 10µs), under_load_latency (p99 < 500µs under 20 readers + writer),
  concurrent_rw (no torn reads, all events processed after sync)

## Bugs fixed (all in CT test infrastructure)
1. market_state:start_link() called from init_per_suite caused the gen_server to die when the
   CT process exited — gen_server records its parent and terminates on parent exit even with
   trap_exit. Fix: added start/0 (gen_server:start, unlinked) to both market_state and game_state;
   test uses start/0 instead of start_link/0.
2. ETS write starvation: 20 tight-loop readers (after 0) held the ETS read lock continuously,
   blocking market_state's ets:insert. Result: 20k publishes took 197 seconds. Fix: changed
   reader_loop to after 1 (1ms sleep), reducing read rate to ~1000 reads/reader/sec and allowing
   writes to proceed normally.
3. Process leak on test failure: spawn/spawn_monitor left writer and readers alive after test
   case exited with writer_timeout, flooding the next test's market_state mailbox. Fix: writer
   uses spawn_link; readers use spawn_opt([link, monitor]).
4. sync() default 5s timeout too short for 20k events under load. Fix: sync() now uses 30_000ms.

## Acceptance gate verified
- make test: all 7 CT tests + PropEr 100/100 + Python 4/4 + Rust passing
- no_load p99 < 10µs ✓
- under_load p99 < 500µs (measured ~184µs) ✓
- concurrent_rw: 0 torn reads, all 20k events processed ✓
- PropEr: 100/100 passes

## Next concrete step
Day 5: strategy_behaviour + always_buy_at_30c
Branch: phase1/day-5-strategy-behaviour

## Blockers
None.

## Notes for next session
- market_state and game_state expose both start_link/0 (for supervised use) and start/0
  (for unlinked/test use) — start/0 is intentional, not a mistake
- ETS with {write_concurrency, true} still serializes on same-bucket operations; under
  heavy concurrent read+write on the same key, reads starve writes without a small yield
- sync() uses 30_000ms timeout; event_bus:publish is fire-and-forget so sync is needed
  to drain market_state's mailbox before asserting ETS state in tests
- inspect:dump/0 is useful for rebar3 shell debugging (ingest-shell target)
