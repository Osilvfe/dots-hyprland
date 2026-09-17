//! 2D 弹性凝胶物理模拟引擎（Jelly Deformation & Spring Dynamics）
//! 基于半隐式阻尼弹簧积分与旋转应变张量，确保即使在帧率波动下也不会发散

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct JellySpringState {
    // 2x2 对称形变矩阵元素 (m00, m01, m11)
    pub dm00: f32,
    pub dm01: f32,
    pub dm11: f32,

    // 形变速度
    pub vel00: f32,
    pub vel01: f32,
    pub vel11: f32,

    // 物理参数
    pub stiffness: f32,
    pub damping: f32,
    pub deform_scale: f32,
    pub max_stretch: f32,

    // 上一帧状态
    pub prev_x: f32,
    pub prev_y: f32,
    pub is_active: bool,
    pub has_prev_pos: bool,
}

impl Default for JellySpringState {
    fn default() -> Self {
        Self {
            dm00: 1.0,
            dm01: 0.0,
            dm11: 1.0,
            vel00: 0.0,
            vel01: 0.0,
            vel11: 0.0,
            stiffness: 240.0,
            damping: 16.0,
            deform_scale: 0.0003,
            max_stretch: 0.35,
            prev_x: 0.0,
            prev_y: 0.0,
            is_active: false,
            has_prev_pos: false,
        }
    }
}

impl JellySpringState {
    pub fn new() -> Self {
        Self::default()
    }

    /// 更新物理帧，传入当前图元中心点的场景世界坐标与时间步长 dt (秒)
    /// 返回是否仍在剧烈运动（true: 需触发重绘, false: 静止）
    pub fn update(&mut self, current_x: f32, current_y: f32, dt: f32) -> bool {
        if !self.has_prev_pos {
            self.prev_x = current_x;
            self.prev_y = current_y;
            self.has_prev_pos = true;
            return false;
        }

        if dt > 0.1 || dt < 0.001 {
            self.prev_x = current_x;
            return self.check_at_rest();
        }

        let vel_x = (current_x - self.prev_x) / dt;
        let vel_y = (current_y - self.prev_y) / dt;
        self.prev_x = current_x;
        self.prev_y = current_y;

        let speed = (vel_x * vel_x + vel_y * vel_y).sqrt();

        if !self.is_active {
            if speed < 5.0 {
                return false;
            }
            self.is_active = true;
        }

        // 计算目标形变张量: R(theta) * diag(stretch, 1/stretch) * R(theta)^T
        let mut target00 = 1.0;
        let mut target01 = 0.0;
        let mut target11 = 1.0;

        if speed > 5.0 {
            let target_stretch = 1.0 + (speed * self.deform_scale).min(self.max_stretch);
            let target_compress = 1.0 / target_stretch;

            let cos_a = vel_x / speed;
            let sin_a = vel_y / speed;
            let cos2 = cos_a * cos_a;
            let sin2 = sin_a * sin_a;
            let cs = cos_a * sin_a;

            target00 = target_stretch * cos2 + target_compress * sin2;
            target01 = (target_stretch - target_compress) * cs;
            target11 = target_stretch * sin2 + target_compress * cos2;
        }

        // 半隐式阻尼弹簧积分
        let inv_damp = 1.0 / (1.0 + self.damping * dt);

        self.vel00 = (self.vel00 - self.stiffness * (self.dm00 - target00) * dt) * inv_damp;
        self.dm00 += self.vel00 * dt;

        self.vel01 = (self.vel01 - self.stiffness * (self.dm01 - target01) * dt) * inv_damp;
        self.dm01 += self.vel01 * dt;

        self.vel11 = (self.vel11 - self.stiffness * (self.dm11 - target11) * dt) * inv_damp;
        self.dm11 += self.vel11 * dt;

        self.check_at_rest()
    }

    /// 检查是否已收敛至静止状态，避免在无形变时持续空转重绘
    fn check_at_rest(&mut self) -> bool {
        let total_delta = (self.dm00 - 1.0).abs() + self.dm01.abs() + (self.dm11 - 1.0).abs();
        let total_vel = self.vel00.abs() + self.vel01.abs() + self.vel11.abs();

        if total_delta < 0.004 && total_vel < 0.05 {
            self.dm00 = 1.0;
            self.dm01 = 0.0;
            self.dm11 = 1.0;
            self.vel00 = 0.0;
            self.vel01 = 0.0;
            self.vel11 = 0.0;
            self.is_active = false;
            false
        } else {
            self.is_active = true;
            true
        }
    }

    /// 获取逆向形变矩阵（用于传递给 GLSL 片元着色器反向采样坐标）
    pub fn get_inv_deform(&self) -> [f32; 4] {
        let det = self.dm00 * self.dm11 - self.dm01 * self.dm01;
        if det.abs() < 1e-6 {
            return [1.0, 0.0, 0.0, 1.0];
        }
        let inv_det = 1.0 / det;
        [
            self.dm11 * inv_det,
            -self.dm01 * inv_det,
            -self.dm01 * inv_det,
            self.dm00 * inv_det,
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spring_convergence() {
        let mut spring = JellySpringState::new();
        // 初始注入快速位移
        spring.update(0.0, 0.0, 0.016);
        spring.update(100.0, 50.0, 0.016);
        assert!(spring.is_active);

        // 停止移动后，经过多帧阻尼振荡收敛
        for _ in 0..120 {
            spring.update(100.0, 50.0, 0.016);
        }

        // 最终应平稳归零回弹至单位矩阵
        assert!(!spring.is_active);
        assert!((spring.dm00 - 1.0).abs() < 0.01);
        assert!(spring.dm01.abs() < 0.01);
        assert!((spring.dm11 - 1.0).abs() < 0.01);
    }
}
