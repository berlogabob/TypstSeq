#ifndef TypstQuickLook_Bridging_Header_h
#define TypstQuickLook_Bridging_Header_h

#include <stddef.h>
#include <stdint.h>

// Mirrors packages/typst_flutter/rust/src/api/quicklook_ffi.rs.
// Kept as a plain C ABI (not flutter_rust_bridge) so the extension can link
// libtypst_flutter.a directly without pulling in the Dart VM bridge.

typedef struct {
    const char *path;
    const uint8_t *bytes;
    size_t bytes_len;
} TypstQlFile;

int32_t typst_ql_compile_pdf(
    const char *markup_utf8,
    const TypstQlFile *files, size_t files_len,
    uint8_t **out_pdf, size_t *out_pdf_len,
    char **out_error
);

void typst_ql_free_bytes(uint8_t *ptr, size_t len);
void typst_ql_free_string(char *ptr);

#endif /* TypstQuickLook_Bridging_Header_h */
