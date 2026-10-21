fn main() {
    // Icon only when building on Windows (CI): the resource compiler is a
    // Windows tool; a cross `cargo check` from macOS skips it.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") && cfg!(windows) {
        winresource::WindowsResource::new()
            .set_icon("../../windows/runner/resources/app_icon.ico")
            .compile()
            .expect("failed to embed launcher icon");
    }
}
