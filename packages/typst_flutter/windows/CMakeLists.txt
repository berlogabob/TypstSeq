cmake_minimum_required(VERSION 3.14)
project(typst_flutter LANGUAGES CXX)

# ── Pre-built binary detection ─────────────────────────────────────────────────
#
# Unlike the other platforms there is no downloadable Windows artifact:
# the .dll is built from the local Rust crate (see the FATAL_ERROR below)
# and placed at:
#   <package_root>/.typst_flutter_prebuilt/windows/typst_flutter.dll
#
# CMAKE_CURRENT_SOURCE_DIR is the plugin's windows/ directory (may be inside the
# pub cache). The consumer app root is two levels up from there:
#   <pub_cache>/typst_flutter-x.y.z/windows/ → ../../ → consumer app root
# (or for a local path dep: <repo>/windows/ → ../../ → consumer app root)
# After building, copy target/release/typst_flutter.dll to the path above
# (CI does this in the windows release job).

set(_prebuilt_dll
  "${CMAKE_CURRENT_SOURCE_DIR}/../.typst_flutter_prebuilt/windows/typst_flutter.dll"
)

if(NOT EXISTS "${_prebuilt_dll}")
  message(FATAL_ERROR
    "typst_flutter: typst_flutter.dll not found at:\n"
    "  ${_prebuilt_dll}\n\n"
    "Run once from your app root:\n"
    "  cargo build --release --manifest-path packages/typst_flutter/rust/Cargo.toml\n"
  )
endif()

# Tell Flutter to bundle the pre-built .dll into the Windows application
set(typst_flutter_bundled_libraries
  "${_prebuilt_dll}"
  PARENT_SCOPE
)
