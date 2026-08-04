#![allow(unexpected_cfgs)]

pub mod api;
#[cfg(target_os = "macos")]
pub mod quicklook_ffi;

#[allow(clippy::all, clippy::not_unsafe_ptr_arg_deref)]
pub mod frb_generated;
