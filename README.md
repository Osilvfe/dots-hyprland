# dots-hyprland (Scrolling Tiling Edition)

基于 [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) 的个人分支，针对 **Hyprland 0.56+ 滚动平铺布局**深度改造。

## 主要变更

### 工作区（Workspace）
- **Niri 风格 per-monitor 工作区**：监视器 0 独占 1-10，监视器 1 独占 11-20，互不干扰
- `SUPER+数字键` 按当前监视器自动映射到正确范围
- 工作区持久化，断连/重连监视器后保持原位

### 概览（Overview）
- `SUPER+Tab` 触发 [hyprland-scroll-overview](https://github.com/yayuuu/hyprland-scroll-overview) 插件
- Compositor 层面缩放视口，无黑窗口问题
- 四指竖滑手势同样触发

### 按键（Keybinds）
- `SUPER+SHIFT+←/→` — 跨屏焦点切换
- `SUPER+CTRL+SHIFT+←/→` — swapcol 列交换
- `SUPER+CTRL+V` — 浮动↔平铺焦点切换

### 字体
- 默认界面字体：PingFang SC（需 `fonts-apple`）
- 等宽字体：JetBrains Mono NF

### 其他
- `render_power = 4` 适配 Hyprland 0.56
- yay → paru
- 仅支持 Arch Linux

## 安装

```bash
# 1. 克隆
git clone https://github.com/Osilvfe/dots-hyprland.git ~/dots-hyprland
cd ~/dots-hyprland

# 2. 安装依赖 + 配置文件
./setup install

# 3. 安装滚动概览插件
sudo mkdir -p /usr/share/hyprpm && sudo chown $USER:$USER /usr/share/hyprpm
hyprpm add https://github.com/yayuuu/hyprland-scroll-overview origin/new-release
hyprpm update
hyprpm enable scrolloverview

# 4. 重启 Hyprland
```
