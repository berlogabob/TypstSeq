cmake_minimum_required(VERSION 3.14)
project(typst_flutter LANGUAGES CXX)

# ── Pre-built binary detection ─────────────────────────────────────────────────
#
# The pre-built .dll is placed by `./tool/setup_typst_native.sh` at:
#   <package_root>/.typst_flutter_prebuilt/windows/typst_flutter.dll
#
# CMAKE_CURRENT_SOURCE_DIR is the plugin's windows/ directory (may be inside the
# pub cache). The consumer app root is two levels up from there:
#   <pub_cache>/typst_flutter-x.y.z/windows/ → ../../ → consumer app root
# (or for a local path dep: <repo>/windows/ → ../../ → consumer app root)

set(_prebuilt_dll
  "${CMAKE_CURRENT_SOURCE_DIR}/../.typst_flutter_prebuilt/windows/typst_flutter.dll"
)

if(NOT EXISTS "${_prebuilt_dll}")
  message(FATAL_ERROR
    "typst_flutter: typst_flutter.dll not found at:\n"
    "  ${_prebuilt_dll}\n\n"
    "Run once from your app root in Git Bash:\n"
    "  TYLOG_SKIP_ANDROID=1 ./tool/setup_typst_native.sh\n"
  )
endif()

# Tell Flutter to bundle the pre-built .dll into the Windows application
set(typst_flutter_bundled_libraries
  "${_prebuilt_dll}"
  PARENT_SCOPE
)
