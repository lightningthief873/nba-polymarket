use std::path::PathBuf;

fn main() {
    let proto_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join("proto");

    let protos = [
        "nba_polymarket/v1/common.proto",
        "nba_polymarket/v1/market.proto",
        "nba_polymarket/v1/game.proto",
        "nba_polymarket/v1/signal.proto",
        "nba_polymarket/v1/order.proto",
    ]
    .map(|p| proto_root.join(p));

    let out_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src/generated");
    std::fs::create_dir_all(&out_dir).unwrap();

    prost_build::Config::new()
        .out_dir(&out_dir)
        .compile_protos(&protos, &[&proto_root])
        .expect("prost-build failed");

    // Re-run only when proto files change.
    println!("cargo:rerun-if-changed={}", proto_root.display());
}
