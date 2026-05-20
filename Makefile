SHELL        := bash
.SHELLFLAGS  := -eu -o pipefail -c
.DEFAULT_GOAL := build

NIF_SRC := nifs/hello/target/release/libhello_nif.so
NIF_DST := apps/core_bus/priv/hello_nif.so

.PHONY: setup build test bench clean shell

setup:
	asdf install
	rebar3 get-deps
	cargo fetch --manifest-path nifs/hello/Cargo.toml

# Rebuild the NIF whenever Rust sources change.
$(NIF_DST): nifs/hello/src/lib.rs nifs/hello/Cargo.toml
	cargo build --manifest-path nifs/hello/Cargo.toml --release
	mkdir -p apps/core_bus/priv
	cp $(NIF_SRC) $(NIF_DST)

# $(NIF_DST) runs first; then rebar3 compile copies priv/ into _build/.
build: $(NIF_DST)
	rebar3 compile

test: build
	rebar3 ct
	rebar3 eunit
	rebar3 proper || true
	cargo test --manifest-path nifs/hello/Cargo.toml --no-default-features

bench:
	@echo "Benchmarks deferred to Day 13"

clean:
	rebar3 clean
	cargo clean --manifest-path nifs/hello/Cargo.toml
	rm -f $(NIF_DST)

shell: build
	rebar3 shell
