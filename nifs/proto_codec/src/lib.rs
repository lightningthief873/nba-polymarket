#[allow(dead_code, clippy::all)]
pub mod generated {
    include!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/generated/nba_polymarket.v1.rs"
    ));
}

pub use generated::*;

/// NIF exports — only compiled when the `nif` feature is enabled.
#[cfg(feature = "nif")]
mod nif {
    use crate::generated::MarketEvent;
    use prost::Message;
    use rustler::{Binary, Env, NifResult, OwnedBinary};

    #[rustler::nif]
    pub fn decode_market_event<'a>(env: Env<'a>, bytes: Binary) -> NifResult<rustler::Term<'a>> {
        let event = MarketEvent::decode(bytes.as_slice())
            .map_err(|e| rustler::Error::Term(Box::new(format!("{e}"))))?;
        let mut out = Vec::new();
        event.encode(&mut out).unwrap();
        let mut bin = OwnedBinary::new(out.len()).unwrap();
        bin.as_mut_slice().copy_from_slice(&out);
        Ok(Binary::from_owned(bin, env).to_term(env))
    }

    rustler::init!("proto_codec_nif");
}
