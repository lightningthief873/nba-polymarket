# nifs/hello — hello_nif

Minimal Rustler NIF proving the Erlang ↔ Rust bridge works.

## Build

Built automatically via `make build` (which runs `cargo build --release`
and copies `libhello_nif.so` → `apps/core_bus/priv/hello_nif.so`).

## Usage

```erlang
1> hello_nif:hello().
<<"hello from rust">>
```

## Notes

- Crate package name is `core_bus` so `rebar3_cargo` maps the output to
  the `core_bus` app's priv directory.
- Library name is `hello_nif`; Erlang loads it via `erlang:load_nif/2`
  triggered by the `-on_load` attribute in `hello_nif.erl`.
- Replace this crate with the real win-probability NIF on Day 14.
