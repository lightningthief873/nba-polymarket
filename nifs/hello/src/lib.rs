fn hello_impl() -> &'static str {
    "hello from rust"
}

// NIF exports are compiled only when the `nif` feature is enabled (default).
// This keeps `cargo test --no-default-features` free of enif_* link deps.
#[cfg(feature = "nif")]
mod nif {
    #[rustler::nif]
    pub fn hello() -> &'static str {
        crate::hello_impl()
    }

    rustler::init!("hello_nif");
}

#[cfg(test)]
mod tests {
    use super::hello_impl;

    #[test]
    fn returns_expected_string() {
        assert_eq!(hello_impl(), "hello from rust");
    }
}
