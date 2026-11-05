#![allow(unexpected_cfgs)]

pub mod api;
#[cfg(any(
    all(target_os = "android", target_arch = "aarch64"),
    all(target_os = "macos", target_arch = "aarch64")
))]
mod lean_tokenizer;
#[cfg(target_os = "macos")]
pub mod quicklook_ffi;

#[allow(clippy::all, clippy::not_unsafe_ptr_arg_deref)]
pub mod frb_generated;

#[cfg(all(test, feature = "p2p-harness"))]
mod p2p_harness_tests;

#[cfg(all(target_os = "android", feature = "p2p-harness"))]
#[unsafe(no_mangle)]
pub extern "system" fn Java_org_tylog_tylog_MainActivity_initP2p(
    env: jni::JNIEnv<'_>,
    _activity: jni::objects::JObject<'_>,
    context: jni::objects::JObject<'_>,
) -> jni::sys::jboolean {
    static INITIALIZED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *INITIALIZED.get_or_init(|| {
        let Ok(vm) = env.get_java_vm() else {
            return false;
        };
        let Ok(global) = env.new_global_ref(context) else {
            return false;
        };
        let context = global.as_obj().as_raw().cast();
        std::mem::forget(global);
        unsafe { iroh::dns::install_android_jni_context(vm.get_java_vm_pointer().cast(), context) };
        true
    }) as jni::sys::jboolean
}
