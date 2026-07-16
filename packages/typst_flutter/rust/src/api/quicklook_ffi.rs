//! Plain C ABI for the macOS Quick Look Preview Extension.
//!
//! Bypasses flutter_rust_bridge entirely (it depends on the Dart VM) and calls
//! the existing [`crate::api::typst::TypstEngine`] directly. Kept in its own
//! module so the Quick Look extension can link against `libtypst_flutter.a`
//! and declare just these symbols in a bridging header.

use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

use crate::api::typst::{TypstEngine, VirtualFile};

#[repr(C)]
pub struct TypstQlFile {
    pub path: *const c_char,
    pub bytes: *const u8,
    pub bytes_len: usize,
}

/// Compiles `markup_utf8` with `files` as the virtual filesystem and writes the
/// resulting PDF bytes to `out_pdf`/`out_pdf_len`.
///
/// Returns 0 on success. On failure, returns a non-zero code and writes a
/// human-readable message to `out_error` (owned by the caller — free with
/// [`typst_ql_free_string`]).
///
/// # Safety
/// `markup_utf8` must be a valid, NUL-terminated UTF-8 C string. `files` must
/// point to `files_len` valid [`TypstQlFile`] entries whose `path`/`bytes`
/// pointers remain valid for the duration of this call. `out_pdf`,
/// `out_pdf_len` and `out_error` must be valid, non-null out-parameters.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn typst_ql_compile_pdf(
    markup_utf8: *const c_char,
    files: *const TypstQlFile,
    files_len: usize,
    out_pdf: *mut *mut u8,
    out_pdf_len: *mut usize,
    out_error: *mut *mut c_char,
) -> i32 {
    unsafe {
        *out_pdf = ptr::null_mut();
        *out_pdf_len = 0;
        *out_error = ptr::null_mut();
    }

    let result = catch_unwind(AssertUnwindSafe(|| unsafe {
        compile_pdf(markup_utf8, files, files_len)
    }));

    match result {
        Ok(Ok(pdf)) => {
            let mut pdf = pdf.into_boxed_slice();
            unsafe {
                *out_pdf_len = pdf.len();
                *out_pdf = pdf.as_mut_ptr();
            }
            std::mem::forget(pdf);
            0
        }
        Ok(Err(message)) => {
            unsafe {
                *out_error = string_to_c(message);
            }
            1
        }
        Err(_) => {
            unsafe {
                *out_error = string_to_c("Internal Typst compiler error (panic).".to_string());
            }
            2
        }
    }
}

unsafe fn compile_pdf(
    markup_utf8: *const c_char,
    files: *const TypstQlFile,
    files_len: usize,
) -> Result<Vec<u8>, String> {
    let markup = unsafe { CStr::from_ptr(markup_utf8) }
        .to_str()
        .map_err(|_| "markup is not valid UTF-8".to_string())?
        .to_string();

    let raw_files = if files_len == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(files, files_len) }
    };
    let mut virtual_files = Vec::with_capacity(raw_files.len());
    for file in raw_files {
        let path = unsafe { CStr::from_ptr(file.path) }
            .to_str()
            .map_err(|_| "file path is not valid UTF-8".to_string())?
            .to_string();
        let bytes = unsafe { slice::from_raw_parts(file.bytes, file.bytes_len) }.to_vec();
        virtual_files.push(VirtualFile { path, bytes });
    }

    let document = TypstEngine::new()
        .compile(markup, virtual_files, None, None)
        .map_err(|err| {
            err.diagnostics
                .iter()
                .map(|d| d.message.clone())
                .collect::<Vec<_>>()
                .join("\n")
        })?;

    document.export_pdf()
}

/// Frees a buffer previously returned via `out_pdf`.
///
/// # Safety
/// `ptr` must be a pointer previously returned by [`typst_ql_compile_pdf`] in
/// `out_pdf`, with the matching `len`, and must not be freed twice.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn typst_ql_free_bytes(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    drop(unsafe { Vec::from_raw_parts(ptr, len, len) });
}

/// Frees a string previously returned via `out_error`.
///
/// # Safety
/// `ptr` must be a pointer previously returned by [`typst_ql_compile_pdf`] in
/// `out_error`, and must not be freed twice.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn typst_ql_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(unsafe { CString::from_raw(ptr) });
}

fn string_to_c(message: String) -> *mut c_char {
    CString::new(message.replace('\0', ""))
        .unwrap_or_default()
        .into_raw()
}
