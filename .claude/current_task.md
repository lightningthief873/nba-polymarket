# Current task

Last updated: 2026-05-20 (Day 2 complete)
Last commit: 379ee93 chore: update Makefile and CI for Day 2 proto targets
Branch: phase1/day-2-protobuf

## Phase: 1
## Day: 2 (DONE — pending PR merge)

## What we are doing right now
Day 2 complete. PR to open, waiting for CI green then merge.

## Done this session
- 5 proto3 schemas: common, market, game, signal, order
  - All enum values SCREAMING_SNAKE_CASE-prefixed (buf STANDARD + proto3 scoping)
- buf lint config (STANDARD, except PACKAGE_VERSION_SUFFIX)
- buf breaking config (FILE mode)
- Erlang codegen: tools/gpb_compile.escript → apps/core_bus/src/generated/*_pb.erl
  - rebar3_gpb_plugin path resolution broken for external protos; escript bypasses it
- Rust codegen: nifs/proto_codec/ crate with prost-build → nba_polymarket.v1.rs
  - Both cdylib (future NIF) + rlib + proto_roundtrip binary
- Python codegen: adapters/proto/nba_polymarket/v1/*_pb2.py via grpcio-tools
- CT test: proto_roundtrip_SUITE — Erlang encodes, Python + Rust round-trip, bytes identical
- Makefile: proto, proto-lint, proto-python, proto-erlang targets; proto_codec in test/clean
- CI: Python 3.12, grpcio-tools, buf install, buf lint/breaking, proto_codec clippy/fmt

## Acceptance gate verified
- make build: exit 0
- rebar3 ct: 3/3 green (hello_nif×2 + proto_roundtrip×1)
- cargo test (hello + proto_codec): all pass
- cargo clippy proto_codec --no-default-features: no warnings
- cargo fmt: clean

## Next concrete step
Day 3: ZMQ wiring + mock publisher
Branch: phase1/day-3-zmq

## Blockers
None.

## Notes for next session
- rebar3_gpb_plugin silently skips proto files outside app dir even with ../../ paths.
  Always use tools/gpb_compile.escript for proto regeneration.
- proto_roundtrip binary needs spawn_executable with a full path; use os:find_executable/1
  in CT tests (spawn_executable does not search PATH).
- Rust crate crate-type = ["cdylib", "rlib"] required so binaries can link against the lib.
- Generated Erlang API: market_pb:encode_msg(Map, market_event) / decode_msg(Bin, market_event)
  Enum atoms: 'SOURCE_POLYMARKET_WS', 'SIDE_BUY', etc. (all prefixed, quoted atoms).
