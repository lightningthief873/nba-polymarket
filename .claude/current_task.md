# Current task

Last updated: 2026-05-20 (Day 1 complete)
Last commit: 97ea588 chore(makefile): setup/build/test/bench/clean/shell targets
Branch: phase1/day-1-umbrella-rustler

## Phase: 1
## Day: 1 (DONE — pending PR merge)

## What we are doing right now
Day 1 complete. PR open, waiting for CI green then merge.

## Done this session
- rebar3 umbrella with 5 OTP apps (core_bus, strategies, execution, persistence, simulator)
- Rust NIF crate at nifs/hello/ (rustler 0.34, feature-gated)
- hello_nif.erl -on_load loader in core_bus
- hello_nif_SUITE.erl — 2 CT tests, both green
- Makefile: setup/build/test/bench/clean/shell
- CI: erlang-rust job with OTP 27 + stable Rust
- docker-compose.yml: QuestDB + Redis (used Day 7)
- Zero dialyzer warnings

## Acceptance gate verified
- make build: exit 0
- make test: exit 0, 2 CT + 1 cargo unit test green
- rebar3 shell + hello_nif:hello() → <<"hello from rust">>
- rebar3 dialyzer: no warnings

## Next concrete step
Day 2: Protobuf schemas + buf + codegen
Branch: phase1/day-2-protobuf

## Blockers
None.

## Notes for next session
- rebar3_cargo v0.1.x looks in app dir for Cargo.toml; not compatible with
  nifs/ layout. Provider_hooks removed; Makefile handles cargo build explicitly.
- cargo test requires --no-default-features to avoid enif_* link errors.
  See nifs/hello/Cargo.toml for `nif` feature flag pattern.
