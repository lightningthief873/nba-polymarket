/// CLI used by the Erlang round-trip CT test.
/// Reads a protobuf-encoded MarketEvent from a file path given as argv[1],
/// decodes it with prost, re-encodes, and writes the raw bytes to stdout.
use prost::Message;
use std::io::Write;

#[allow(dead_code, clippy::all)]
mod generated {
    include!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/generated/nba_polymarket.v1.rs"
    ));
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: proto_roundtrip <input_file>");
        std::process::exit(1);
    }
    let raw = std::fs::read(&args[1]).expect("read input file");
    let event = generated::MarketEvent::decode(raw.as_slice()).expect("prost decode");
    let mut out = Vec::with_capacity(raw.len());
    event.encode(&mut out).expect("prost encode");
    std::io::stdout().write_all(&out).expect("write stdout");
}
