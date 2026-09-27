#![allow(unexpected_cfgs)]

pub mod api;
#[cfg(any(all(target_os = "android", target_arch = "aarch64"), all(target_os = "macos", target_arch = "aarch64")))]
mod lean_tokenizer;
#[cfg(target_os = "macos")]
pub mod quicklook_ffi;

#[allow(clippy::all, clippy::not_unsafe_ptr_arg_deref)]
pub mod frb_generated;
