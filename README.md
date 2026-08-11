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

### 顶栏媒体歌词（Quickshell/II 定制）
- **实时歌词**：通过 [SPlayer-Next](https://github.com/SPlayer-Dev/SPlayer-Next) 外部 API 显示当前句歌词到顶栏（需在 SPlayer 设置开启 external API）
- **WebSocket 事件驱动**：`track`/`lyric`/`status` 事件即时推送切歌/歌词/播放态；position 本地时钟推算 + 低频 HTTP 校准；WS 不可用时自动降级 HTTP 轮询
- **间奏识别**：长器乐间隙（行间或尾部 outro ≥4s）显示 `♪ ♪ ♪` 音符指示（如蓝莲花 96s 尾部纯音乐）
- 歌词超长时 ghost 无缝 marquee 滚动，支持切歌/暂停/滚动对齐

### 截图 / 录屏 / 录音（SUPER+SHIFT+S）
- 选区工具栏：取色器、录屏、录 GIF、录麦克风、录系统声音
- 录屏走 wf-recorder（系统+麦克风多源混音），录音存 `~/Music`
- 顶栏录制指示器（点击停止），IPC 驱动状态

### 系统托盘（SNI）
- qs 保持纯 host；kded6 作为 watcher（qs 启动时自动拉起），托盘图标跨 qs 重启不丢失
- 已禁用 kded6 `devicenotifications`（纯 Hyprland 下崩溃）

### 日历 / 节假日
- 侧栏日历显示中文节假日：节日名 + 休/班标记（Nager.Date + holiday-cn 双数据源，离线缓存）

### 搜索框 / emoji
- `SUPER` 单按 toggle 搜索框，支持 emoji 面板（SUPER+Period）、剪贴板历史（SUPER+V）

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
