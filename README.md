# dots-hyprland (Scrolling Tiling Edition)

基于 [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) 的个人分支，针对 **Hyprland 0.56+ 滚动平铺布局**深度改造。

## 主要变更

### 工作区（Workspace）
- **Niri 风格 per-monitor 工作区**：监视器按顺序各占 10 个编号（第一台 1–10，第二台 11–20），`SUPER+数字键` 映射到当前监视器那一组
- 用 Hyprland `workspace_rule` 把编号绑到对应 `monitor:`，不是断连后窗口位置的持久化

### 概览（Overview）
- `SUPER+Tab` 触发 [hyprland-scroll-overview](https://github.com/yayuuu/hyprland-scroll-overview) 插件
- Compositor 层面缩放视口，无黑窗口问题
- 四指竖滑手势同样触发

### 按键（Keybinds）
- `SUPER` 单按 — toggle 搜索框（松开触发）
- `SUPER+SHIFT+←/→` — 跨屏焦点切换
- `SUPER+CTRL+SHIFT+←/→` — swapcol 列交换
- `SUPER+CTRL+V` — 浮动↔平铺焦点切换
- `SUPER+V` 剪贴板；`SUPER+Period` emoji；`SUPER+SHIFT+S` 截图/录制工具栏

### 字体
- 默认界面字体：PingFang SC（`illogical-impulse-fonts-themes` 依赖 `fonts-apple`）
- 等宽字体：JetBrains Mono NF（kitty / 代码块）

### 顶栏媒体歌词（Quickshell/II 定制）
- **实时歌词**：通过 [SPlayer-Next](https://github.com/SPlayer-Dev/SPlayer-Next) 外部 API 显示当前句歌词到顶栏（需在 SPlayer 设置开启 external API）
- **WebSocket 事件驱动**：`track`/`lyric`/`status` 事件即时推送切歌/歌词/播放态；position 本地时钟推算 + 低频 HTTP 校准；WS 不可用时自动降级 HTTP 轮询
- **间奏识别**：行间或尾部 outro 间隙 ≥4s 显示音符指示
- 歌词超长时 ghost 无缝 marquee 滚动，支持切歌/暂停/滚动对齐

### 截图 / 录屏 / 录音（SUPER+SHIFT+S）
- 选区工具栏：取色器、录屏、录 GIF、录麦克风、录系统声音
- 录屏走 wf-recorder（系统+麦克风可多源混音），录音存 `~/Music`
- 顶栏录制指示器（点击停止），IPC 驱动状态

### 系统托盘（SNI）
- **qs 自建 StatusNotifierWatcher**；安装后执行 `mask_kded6.sh`，避免 kded6 抢 watcher
- `pkill -x qs` 重启会丢掉 QQ/微信（Electron 只注册一次）图标，需重开对应应用
- 已禁用 kded6 `devicenotifications`（纯 Hyprland 下崩溃；kded6 读的是 `kded5rc`）

### 日历 / 节假日
- 侧栏日历显示中文节假日：节日名 + 休/班标记（Nager.Date 定节日当天，holiday-cn 定放假/调休，离线缓存）

### 其他
- 窗口阴影 `render_power = 4`
- 包管理：Arch 安装脚本用 paru（不再用 yay）
- 仅支持 Arch Linux

## 安装

```bash
# 1. 克隆
git clone https://github.com/Osilvfe/dots-hyprland.git ~/dots-hyprland
cd ~/dots-hyprland

# 2. 安装依赖 + 配置文件（会尝试安装 scrolloverview 插件）
./setup install

# 3. 若 hyprpm 未装上插件，再手动：
sudo mkdir -p /usr/share/hyprpm && sudo chown "$USER:$USER" /usr/share/hyprpm
hyprpm add https://github.com/yayuuu/hyprland-scroll-overview origin/new-release
hyprpm update
hyprpm enable scrolloverview

# 4. 重启 Hyprland
```

## Credits

本项目基于以下开源项目与贡献，特此致谢：

- **上游基础**：[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) — 本项目的一切来源于此，Quickshell/II shell 与 Hyprland 配置框架均继承自上游

