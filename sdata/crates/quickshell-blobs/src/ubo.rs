//! std140 严格内存对齐的 UBO 打包器，直接服务于 GPU 片元着色器 (blob.frag)

pub const MAX_RECTS: usize = 16;
pub const UBO_TOTAL_SIZE: usize = 1440;

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct BlobRectData {
    pub cx: f32,
    pub cy: f32,
    pub hw: f32,
    pub hh: f32,

    pub offset_x: f32,
    pub offset_y: f32,
    pub min_eig: f32,
    pub inv_deform: [f32; 4],
    pub screen_half_x: f32,
    pub screen_half_y: f32,
    pub radius: [f32; 4],
    pub exclude_mask: i32,
}


impl Default for BlobRectData {
    fn default() -> Self {
        Self {
            cx: 0.0,
            cy: 0.0,
            hw: 0.0,
            hh: 0.0,
            offset_x: 0.0,
            offset_y: 0.0,
            min_eig: 1.0,
            inv_deform: [1.0, 0.0, 0.0, 1.0],
            screen_half_x: 0.0,
            screen_half_y: 0.0,
            radius: [0.0; 4],
            exclude_mask: 0,
        }
    }
}

#[repr(C)]
#[derive(Debug, Clone)]
pub struct BlobUboState {
    pub matrix: [f32; 16],
    pub opacity: f32,
    pub padded_rect: [f32; 4], // x, y, w, h
    pub smooth_factor: f32,
    pub rect_count: i32,
    pub my_index: i32,
    pub color: [f32; 4], // r, g, b, a
    pub inverted_radii: [f32; 4], // tr, br, bl, tl
    pub inverted_outer: [f32; 4],
    pub inverted_inner: [f32; 4],
    pub rects: [BlobRectData; MAX_RECTS],
}

impl Default for BlobUboState {
    fn default() -> Self {
        Self {
            matrix: [
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.0, 0.0, 0.0, 1.0,
            ],
            opacity: 1.0,
            padded_rect: [0.0; 4],
            smooth_factor: 32.0,
            rect_count: 0,
            my_index: -2,
            color: [0.267, 0.533, 1.0, 1.0],
            inverted_radii: [0.0; 4],
            inverted_outer: [0.0; 4],
            inverted_inner: [0.0; 4],
            rects: [BlobRectData::default(); MAX_RECTS],
        }
    }
}

impl BlobUboState {
    /// 将 UBO 状态打包至给定的连续字节缓冲区中（要求缓冲区长度 >= 1440）
    pub fn pack_into(&self, dest: &mut [u8]) -> Result<(), &'static str> {
        if dest.len() < UBO_TOTAL_SIZE {
            return Err("Destination buffer too small, requires 1440 bytes");
        }

        // 0..64: 4x4 matrix
        for i in 0..16 {
            dest[i * 4..(i + 1) * 4].copy_from_slice(&self.matrix[i].to_ne_bytes());
        }

        // 64..68: opacity
        dest[64..68].copy_from_slice(&self.opacity.to_ne_bytes());

        // 68..84: padded rect (x, y, w, h)
        for i in 0..4 {
            let offset = 68 + i * 4;
            dest[offset..offset + 4].copy_from_slice(&self.padded_rect[i].to_ne_bytes());
        }

        // 84..88: smooth factor
        dest[84..88].copy_from_slice(&self.smooth_factor.to_ne_bytes());

        // 88..92: rect count
        dest[88..92].copy_from_slice(&self.rect_count.to_ne_bytes());

        // 92..96: my index
        dest[92..96].copy_from_slice(&self.my_index.to_ne_bytes());

        // 96..112: color (r, g, b, a)
        for i in 0..4 {
            let offset = 96 + i * 4;
            dest[offset..offset + 4].copy_from_slice(&self.color[i].to_ne_bytes());
        }

        // 112..128: inverted radii (tr, br, bl, tl)
        for i in 0..4 {
            let offset = 112 + i * 4;
            dest[offset..offset + 4].copy_from_slice(&self.inverted_radii[i].to_ne_bytes());
        }

        // 128..144: inverted outer vec4
        for i in 0..4 {
            let offset = 128 + i * 4;
            dest[offset..offset + 4].copy_from_slice(&self.inverted_outer[i].to_ne_bytes());
        }

        // 144..160: inverted inner vec4
        for i in 0..4 {
            let offset = 144 + i * 4;
            dest[offset..offset + 4].copy_from_slice(&self.inverted_inner[i].to_ne_bytes());
        }

        // 160..1440: rect data (each 80 bytes)
        let count = self.rect_count.clamp(0, MAX_RECTS as i32) as usize;
        for i in 0..count {
            let r = &self.rects[i];
            let base = 160 + i * 80;

            // vec4 d0: cx, cy, hw, hh
            dest[base..base + 4].copy_from_slice(&r.cx.to_ne_bytes());
            dest[base + 4..base + 8].copy_from_slice(&r.cy.to_ne_bytes());
            dest[base + 8..base + 12].copy_from_slice(&r.hw.to_ne_bytes());
            dest[base + 12..base + 16].copy_from_slice(&r.hh.to_ne_bytes());

            // vec4 d1: excludeMask (as float bit-cast), offsetX, offsetY, minEig
            let mask_float = f32::from_bits(r.exclude_mask as u32);
            dest[base + 16..base + 20].copy_from_slice(&mask_float.to_ne_bytes());
            dest[base + 20..base + 24].copy_from_slice(&r.offset_x.to_ne_bytes());
            dest[base + 24..base + 28].copy_from_slice(&r.offset_y.to_ne_bytes());
            dest[base + 28..base + 32].copy_from_slice(&r.min_eig.to_ne_bytes());

            // vec4 d2: invDeform (4 floats)
            for j in 0..4 {
                let off = base + 32 + j * 4;
                dest[off..off + 4].copy_from_slice(&r.inv_deform[j].to_ne_bytes());
            }

            // vec4 d3: screenHalfX, screenHalfY, 0.0, 0.0
            dest[base + 48..base + 52].copy_from_slice(&r.screen_half_x.to_ne_bytes());
            dest[base + 52..base + 56].copy_from_slice(&r.screen_half_y.to_ne_bytes());
            dest[base + 56..base + 60].fill(0);
            dest[base + 60..base + 64].fill(0);

            // vec4 d4: radius (tr, br, bl, tl)
            for j in 0..4 {
                let off = base + 64 + j * 4;
                dest[off..off + 4].copy_from_slice(&r.radius[j].to_ne_bytes());
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ubo_buffer_size() {
        let mut buf = vec![0u8; UBO_TOTAL_SIZE];
        let mut state = BlobUboState::default();
        state.rect_count = 2;
        assert!(state.pack_into(&mut buf).is_ok());
    }
}
