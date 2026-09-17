//! quickshell-blobs: High-performance fluid morphing SDF & jelly physics engine in Rust

pub mod physics;
pub mod ubo;

use physics::JellySpringState;
use ubo::{BlobUboState, UBO_TOTAL_SIZE};

/// 创建一个新的物理模拟弹簧对象句柄
#[no_mangle]
pub extern "C" fn blob_spring_create() -> *mut JellySpringState {
    Box::into_raw(Box::new(JellySpringState::new()))
}

/// 销毁物理模拟弹簧对象句柄
#[no_mangle]
pub extern "C" fn blob_spring_destroy(ptr: *mut JellySpringState) {
    if !ptr.is_null() {
        unsafe {
            drop(Box::from_raw(ptr));
        }
    }
}

/// 更新物理模拟帧
#[no_mangle]
pub extern "C" fn blob_spring_update(
    ptr: *mut JellySpringState,
    current_x: f32,
    current_y: f32,
    dt: f32,
    out_inv_deform: *mut f32, // 长度至少为 4
) -> bool {
    if ptr.is_null() {
        return false;
    }
    let spring = unsafe { &mut *ptr };
    let active = spring.update(current_x, current_y, dt);

    if !out_inv_deform.is_null() {
        let inv = spring.get_inv_deform();
        unsafe {
            std::ptr::copy_nonoverlapping(inv.as_ptr(), out_inv_deform, 4);
        }
    }

    active
}

/// 配置弹簧物理参数
#[no_mangle]
pub extern "C" fn blob_spring_configure(
    ptr: *mut JellySpringState,
    stiffness: f32,
    damping: f32,
    deform_scale: f32,
) {
    if let Some(spring) = unsafe { ptr.as_mut() } {
        spring.stiffness = stiffness;
        spring.damping = damping;
        spring.deform_scale = deform_scale;
    }
}

/// 创建新的 UBO 状态对象句柄
#[no_mangle]
pub extern "C" fn blob_ubo_create() -> *mut BlobUboState {
    Box::into_raw(Box::new(BlobUboState::default()))
}

/// 销毁 UBO 状态对象句柄
#[no_mangle]
pub extern "C" fn blob_ubo_destroy(ptr: *mut BlobUboState) {
    if !ptr.is_null() {
        unsafe {
            drop(Box::from_raw(ptr));
        }
    }
}

/// 将 UBO 状态安全打包写入目标连续内存区（dest 指针，长度 len 必须 >= 1440）
#[no_mangle]
pub extern "C" fn blob_ubo_pack(
    ubo_ptr: *const BlobUboState,
    dest_ptr: *mut u8,
    dest_len: usize,
) -> bool {
    if ubo_ptr.is_null() || dest_ptr.is_null() || dest_len < UBO_TOTAL_SIZE {
        return false;
    }
    let state = unsafe { &*ubo_ptr };
    let dest_slice = unsafe { std::slice::from_raw_parts_mut(dest_ptr, dest_len) };
    state.pack_into(dest_slice).is_ok()
}
