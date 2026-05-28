SHELL        := bash
.SHELLFLAGS  := -eu -o pipefail -c
.DEFAULT_GOAL := build

NIF_SRC         := nifs/hello/target/release/libhello_nif.so
NIF_DST         := apps/core_bus/priv/hello_nif.so
ROUNDTRIP_BIN   := nifs/proto_codec/target/debug/proto_roundtrip

.PHONY: setup proto build test bench clean shell mock-publish ingest-shell

setup:
	asdf install
	rebar3 get-deps
	cargo fetch --manifest-path nifs/hello/Cargo.toml
	cargo fetch --manifest-path nifs/proto_codec/Cargo.toml
	pip3 install --quiet grpcio-tools protobuf
	pip3 install --quiet -r adapters/mock_publisher/requirements.txt

# Lint proto files with buf.
proto-lint:
	cd proto && buf lint

# Regenerate Python stubs.
proto-python:
	python3 -m grpc_tools.protoc \
	    -I proto \
	    --python_out=adapters/proto \
	    --pyi_out=adapters/proto \
	    proto/nba_polymarket/v1/common.proto \
	    proto/nba_polymarket/v1/market.proto \
	    proto/nba_polymarket/v1/game.proto \
	    proto/nba_polymarket/v1/signal.proto \
	    proto/nba_polymarket/v1/order.proto

# Regenerate Erlang stubs via the custom escript.
proto-erlang:
	rebar3 compile --deps_only
	escript tools/gpb_compile.escript

# Build the Rust proto_roundtrip CLI (debug is fine for tests).
$(ROUNDTRIP_BIN): nifs/proto_codec/src/bin/proto_roundtrip.rs \
                  nifs/proto_codec/src/lib.rs \
                  nifs/proto_codec/build.rs \
                  nifs/proto_codec/Cargo.toml
	cargo build --manifest-path nifs/proto_codec/Cargo.toml \
	            --no-default-features --bin proto_roundtrip

proto: proto-lint proto-python proto-erlang $(ROUNDTRIP_BIN)

# Rebuild the hello NIF whenever Rust sources change.
$(NIF_DST): nifs/hello/src/lib.rs nifs/hello/Cargo.toml
	cargo build --manifest-path nifs/hello/Cargo.toml --release
	mkdir -p apps/core_bus/priv
	cp $(NIF_SRC) $(NIF_DST)

build: $(NIF_DST) $(ROUNDTRIP_BIN)
	rebar3 compile

test: build
	rebar3 ct
	rebar3 eunit
	rebar3 proper --module event_bus_prop,market_state_prop,strategy_behaviour_prop,position_tracker_prop || true
	cargo test --manifest-path nifs/hello/Cargo.toml --no-default-features
	cargo test --manifest-path nifs/proto_codec/Cargo.toml --no-default-features
	python3 -m pytest adapters/mock_publisher/tests/ -v

## Run the mock publisher for 30s at 1000 evt/sec (manual smoke test).
mock-publish:
	python3 adapters/mock_publisher/main.py \
	    --rate 1000 --duration 30 --seed 42

## Start rebar3 shell with core_bus (and therefore ingest_subscriber) running.
ingest-shell: build
	rebar3 shell --apps core_bus

bench:
	@echo "Benchmarks deferred to Day 13"

clean:
	rebar3 clean
	cargo clean --manifest-path nifs/hello/Cargo.toml
	cargo clean --manifest-path nifs/proto_codec/Cargo.toml
	rm -f $(NIF_DST)

shell: build
	rebar3 shell
