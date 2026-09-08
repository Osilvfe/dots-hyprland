# dots-hyprland (Scrolling Tiling Edition)

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?logo=arch-linux&logoColor=fff&style=flat-square)](https://archlinux.org/)
[![Hyprland 0.56](https://img.shields.io/badge/Hyprland-0.56_Lua-00ACC1?logo=wayland&logoColor=fff&style=flat-square)](https://hyprland.org/)
[![Quickshell](https://img.shields.io/badge/Quickshell-II_Shell-8A2BE2?style=flat-square)](https://quickshell.outfoxxed.me/)
[![Wayland](https://img.shields.io/badge/Wayland-Native-2E8B57?style=flat-square)](https://wayland.freedesktop.org/)
[![Rust](https://img.shields.io/badge/Rust-Helpers-DEA584?logo=rust&logoColor=fff&style=flat-square)](https://www.rust-lang.org/)

基于 [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) 深度定制的现代化、模块化个人桌面配置分支。融合 **Niri 风格多屏滚动平铺**、**全套 Quickshell / Material You 桌面组件**、**零依赖 Rust 原生底层辅助模块** 以及深度的系统/外设硬件整合，专为追求丝滑流动感与高效率的 Arch Linux 用户打造。

---

## 目录
- [✨ 核心亮点](#-核心亮点)
  - [1. 平铺与流动动效 (Scrolling Tiling & Fluid Dynamics)](#1-平铺与流动动效)
  - [2. Quickshell / II 现代桌面体系](#2-quickshell--ii-现代桌面体系)
  - [3. 智能剪贴板 (Smart Clipboard Inspector)](#3-智能剪贴板)
  - [4. OnePlus Buds 3 原生硬件级控制](#4-oneplus-buds-3-原生硬件级控制)
  - [5. PipeWire 分设备硬件级 EQ 与曲线可视化](#5-pipewire-分设备硬件级-eq-与曲线可视化)
  - [6. 以太网 (RJ45) 与网络中枢](#6-以太网-rj45-与网络中枢)
  - [7. 系统录制与多媒体生态](#7-系统录制与多媒体生态)
  - [8. 底层极客优化 (Rust Native Helpers)](#8-底层极客优化)
- [⌨️ 常用快捷键速查](#️-常用快捷键速查)
- [🚀 安装与快速上手](#-安装与快速上手)
- [📂 仓库布局与同步规范](#-仓库布局与同步规范)
- [❤️ 致谢 (Credits)](#️-致谢-credits)

---

## ✨ 核心亮点

### 1. 平铺与流动动效
- **Niri 风格 Per-Monitor 工作区**：监视器按物理顺序各占 10 个独立编号（第一台 1–10，第二台 11–20…），通过 `workspace_rule` 将编号与监视器绑定，`SUPER+数字键` 自动定位到当前屏幕对应组。
- **真弹簧物理动效**：工作区竖向切换采用临界阻尼弹簧（`niriWorkspace`，mass=1, stiffness=1000, dampening=63.2，约 250ms 收住无回弹）；窗口打开/关闭采用微量弹性回弹（`niriOpen` / `niriClose`）。
- **无黑屏视口概览**：`SUPER+Tab` 或触控板四指竖滑手势唤出 [hyprland-scroll-overview](https://github.com/yayuuu/hyprland-scroll-overview) 插件，在 Compositor 层面平滑缩放视口。
- **模块化 Lua 入口**：Hyprland 0.56 原生 Lua 配置，全模块解耦（`variables.lua`、`general.lua`、`rules.lua`、`keybinds.lua` 等）。

### 2. Quickshell / II 现代桌面体系
- **顶栏（Top Bar）**：
  - **SPlayer-Next 媒体歌词**：通过 WebSocket 事件驱动对接 SPlayer-Next 外部 API，显示逐字时间轴卡拉OK滚动，支持智能间奏（Interlude ≥4s）音符提示。
  - **TWS 双耳耳机电量指示**：支持左右单耳与电池盒三电量独立检测，自适应呈现低电量耳或双耳模式，搭配专用 Material 图标（`earbuds_2`、`earbud_left`、`earbud_right`、`earbud_case`）。
  - **系统常驻指标**：勿休眠咖啡杯（Idle Inhibitor）、动态蓝牙电量、系统资源微监视器、网络指示器。
  - **稳定 SNI 系统托盘**：Quickshell 自建 `org.kde.StatusNotifierWatcher`，配合 `mask_kded6.sh` 阻止 KDE 服务抢占，托盘图标不再失效丢失。
- **Material You 动态主题系统**：
  - 根据壁纸实时提取 Material 3 动态色彩体系，提供 10 个主题快照槽位（壁纸、明暗模式、自定义主色一键保存与切换）。
- **侧边栏与日历**：
  - 中文日历公历农历双轨支持：节日当天精确对应，搭配中国法定节假日与调休补班彩色徽章（“休”/“班”），离线多轨缓存保障离线可用。

### 3. 智能剪贴板
按 `SUPER+V`（或在 Overview 搜索框输入 `:clip`）即可开启纯本地运行的智能剪贴板工坊（`ClipboardInspector.qml`），**零网络请求、零外部依赖、微秒级即时响应**：
- **颜色代码感知**：自动识别 `#HEX`、`rgb(a)`、`hsl(a)`，列表直观渲染真实圆形色块徽章，右侧动态注入 `HEX ↔ RGB ↔ HSL` 格式一键转换复制动作。
- **算术算式求解**：纯本地安全求值加减乘除、乘方、括号、开方、常用数学函数与十六进制，就地呈现 `= 结果` 胶囊徽章并支持一键复制结果。
- **时间戳换算**：自动匹配秒/毫秒级 Unix 时间戳，按本地时区换算为 `YYYY-MM-DD HH:mm:ss` 及相对时间描述（如“刚刚”、“5 分钟前”），提供格式化与 ISO 8601 一键复制。
- **本地路径与链接直达**：识别有效 URL 链接提供一键浏览器打开；识别本地系统文件路径提供直接调用关联程序打开及快速定位上级文件夹。
- **格式清洗与解码**：自动检验 JSON 并提供 Pretty 格式化与单行 Minify 压缩；纯本地解码可读 Base64 文本。

### 4. OnePlus Buds 3 原生硬件级控制
专为 OnePlus Buds 3（一加 Buds 3）定制的 Linux 桌面控制中心：
- **纯 Rust 原生 RFCOMM/SPP 桥接器**：直接基于 Linux 原生 Bluetooth 套接字与专属 SPP 协议帧通信，无 Python 解释器启动延迟，无任何第三方 Crate 依赖，由 `rustc -O` 自动编译缓存。
- **主从 QML 解耦架构**：
  - 主桌面 Shell（`isServer: true`）唯一持有底层连接通道，实时维护电量与控制通路，状态写入 `$XDG_RUNTIME_DIR/quickshell-oplus-buds3.json`；
  - 独立设置窗口（`isServer: false`）作为纯 UI 客户端，通过 IPC 通信和状态复用，彻底杜绝多窗口争抢信道与重连死锁。
- **完整功能控制**：降噪（ANC 深度/中度/轻度/智能）、通透模式、个性化黄金听感、Master EQ 预设、空间音频、游戏低延迟模式、双设备切换与佩戴检测。

### 5. PipeWire 分设备硬件级 EQ 与曲线可视化
- **物理 Sink 零损耗挂载**：直接将滤镜图（`filter-graph`）附加到物理音频设备节点，无需创建会破坏默认路由的虚拟声卡。
- **交互式对数频响曲线（`EqCurveView.qml`）**：
  - 呈现 20 Hz – 20 kHz 标准对数频响响应图，支持自适应 dB 刻度、0 dB 参考基准线与半透明渐变填充。
  - 鼠标悬停动态探针，实时显示光标所在频段增益（Hz / dB）及对应频段调节节点。
- **全格式曲线导入**：支持标准 AutoEQ 参数化 EQ（`ParametricEQ.txt`）与无表头两列频响数据（由后端自动转换并生成多采样率最小相位 FIR 脉冲卷积）。
- **系统级声音设置中心（`SoundConfig.qml`）**：物理输入输出快速切换、麦克风增益调节、应用音量混音器、系统提示音开关与防爆音音量保护。

### 6. 以太网 (RJ45) 与网络中枢
- **设置页原生以太网卡片（`EthernetSection.qml`）**：
  - 采用纯 Rust 原生硬件与链路探测模块（`ethernet-info.rs`），消除 Python 启动耗时。
  - 实时检测网线插入/载波状态、协商速率（如 1000 Mb/s）、硬件 MAC 地址、IPv4/IPv6、网关及 DNS 服务器，支持快速一键复制。
  - 支持有线网络自动连接开关以及手动连接/断开。
- **Clash Verge Rev 集成**：控制中心面板提供专属 TUN 虚拟网卡模式与系统代理独立开关图块。

### 7. 系统录制与多媒体生态
- **快捷截图菜单（`SUPER+SHIFT+S`）**：选区工具栏集成取色器、区域/窗口截图、录屏（MP4）、录制动图（GIF）、录制麦克风及录制系统声音（支持多声道独立混音）。
- **录制状态胶囊**：录制进行时顶栏显示红色录制指示胶囊与计时器，支持一键点击优雅封装并停止录制。

### 8. 底层极客优化
- **Rust Native Helpers**：关键常驻或高频调用脚本全面重构为原生 Rust（`gamepad-active.rs`、`ethernet-info.rs`、`oplus-buds3-bridge.rs`），零依赖通过 `rustc -O` 缓存至 `~/.cache/`，替代 Python 脚本消除进程启动耗时。
- **智能防休眠手柄探测**：`gamepad-active.rs` 直接调用 Linux 内核 `evdev` 的 `EVIOCGBIT` 与 `poll` 系统调用，打游戏时按下按键自动抑制 `hypridle` 锁屏与系统休眠。

---

## ⌨️ 常用快捷键速查

| 快捷键 | 功能描述 |
| :--- | :--- |
| **`SUPER`（单按松开）** | 打开 / 关闭应用搜索与启动器（Overview Search） |
| **`SUPER + V`** | 呼出智能剪贴板历史（支持颜色/算式/时间戳/路径智能动作） |
| **`SUPER + Tab`** | 切换滚动平铺全览模式（`scrolloverview` 插件 / 四指竖滑） |
| **`SUPER + Period` (`.`)** | 呼出 Emoji 选择器面板 |
| **`SUPER + SHIFT + S`** | 截屏与屏幕录制交互式工具栏（选区/录屏/录GIF/音频） |
| **`Print`** | 全屏截图复制到剪贴板 |
| **`CTRL + Print`** | 全屏截图并保存至 `~/Pictures/Screenshots` |
| **`SUPER + SHIFT + A`** | 选区图片搜索（Snip to Search） |
| **`SUPER + SHIFT + X`** | 选区文字识别（OCR 提取文本到剪贴板） |
| **`SUPER + 1..0`** | 切换至当前屏幕对应的工作区（第一屏 1-10，第二屏 11-20） |
| **`SUPER + SHIFT + 1..0`** | 将当前窗口移动至当前屏幕对应的工作区 |
| **`SUPER + SHIFT + ← / →`** | 跨显示器焦点切换 |
| **`SUPER + CTRL + SHIFT + ← / →`** | 滚动平铺列位置交换（Swap Column） |
| **`SUPER + CTRL + V`** | 浮动窗口与平铺窗口焦点快速切换 |
| **`SUPER + Q`** | 关闭当前聚焦窗口 |

---

## 🚀 安装与快速上手

> [!NOTE]
> 本配置仅支持 **Arch Linux**。包管理器要求配置好 `paru`。

### 1. 克隆仓库
```bash
git clone https://github.com/Osilvfe/dots-hyprland.git ~/dots-hyprland
cd ~/dots-hyprland
```

### 2. 运行自动化安装
安装脚本会自动安装必要的核心组件、依赖包、字体（Google Sans Flex / JetBrains Mono NF）以及配置部署：
```bash
./setup install
```

### 3. 安装与启用滚动概览插件
若自动化安装未成功安装插件，可手动初始化 `hyprpm`：
```bash
sudo mkdir -p /usr/share/hyprpm && sudo chown -R "$USER:$USER" /usr/share/hyprpm
hyprpm add https://github.com/yayuuu/hyprland-scroll-overview origin/new-release
hyprpm update
hyprpm enable scrolloverview
```

### 4. 重载与启动
重新登录或启动 Hyprland 即可体验完整桌面环境！

---

## 📂 仓库布局与同步规范

- `dots/.config/`：**配置部署源**，所有实际生效的配置均应修改此目录下的源文件：
  - `dots/.config/hypr/`：Hyprland Lua 配置、快捷键、动画与脚本；
  - `dots/.config/quickshell/ii/`：Quickshell 主 Shell、组件模块、单例服务与辅助工具；
- `sdata/dist-arch/`：本地自维护的 AUR 包 PKGBUILD 与 patch；
- `AGENTS.md`：详细的维护与开发规约文档。

> [!IMPORTANT]
> 修改 `dots/` 下的内容后，需同步部署到 `~/.config/`（例如 `cp -f`）。
> 修改 Quickshell 组件后，需清理缓存并重载：
> ```bash
> rm -rf ~/.cache/quickshell/qmlcache && pkill -x qs && nohup qs -c ii &
> ```

---

## ❤️ 致谢 (Credits)

本项目基于开源社区的大量杰出贡献与灵感构建，在此致以诚挚敬意：

- **上游基石**：[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) —— 优秀的 Quickshell / II 框架与精美的 Material You 桌面设计原点。
- **窗口合成器**：[Hyprland](https://hyprland.org/) —— 性能强劲且高度可扩展的 Wayland 动态平铺合成器。
- **Shell 引擎**：[Quickshell](https://quickshell.outfoxxed.me/) —— 基于 Qt/QML 构建的原生 Wayland 桌面组件系统。
- **概览插件**：[hyprland-scroll-overview](https://github.com/yayuuu/hyprland-scroll-overview) —— 为滚动平铺量身定制的高性能视口概览。
- **蓝牙耳机逆向研究**：[OppoPodsManager-linux](https://github.com/Osilvfe/OppoPodsManager-linux) —— OnePlus Buds 3 蓝牙 SPP 协议逆向与实现基础。
- **媒体歌词支持**：[SPlayer-Next](https://github.com/SPlayer-Dev/SPlayer-Next) —— 提供优雅的外部歌词 API 与逐字时间轴。
