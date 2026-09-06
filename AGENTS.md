# AGENTS.md

本项目是基于 end-4/dots-hyprland 的 Hyprland 配置（Hyprland 0.56 Lua 配置 + Quickshell/II shell，仅 Arch Linux）。

## 项目结构

### 仓库布局
- `dots/.config/` —— 全部配置（**部署源**），子目录即 `~/.config/<name>/`
- `sdata/dist-arch/` —— 自维护的 AUR 包 PKGBUILD 与 patch（`illogical-impulse-*`）
- `AGENTS.md` —— 本文档
- 远端：`origin`=Osilvfe/dots-hyprland（推送）、`upstream`=end-4 原仓库（仅跟踪）、`quickshell-sample`=StatIndet/quickshell（参考，不合并）

### Hyprland 配置（`dots/.config/hypr/`）
- `hyprland.lua` —— 入口，逐段 require 下面各 lua
- `hyprland/` 下的 lua 模块：
  - `variables.lua` / `env.lua`（环境变量：XCURSOR_SIZE、OZONE、`XDG_DATA_DIRS` 去重等）/ `colors.lua`（色板）/ `general.lua`（通用+动画+插件守卫）/ `rules.lua`（窗口规则+XWayland no_blur+per-monitor 工作区）/ `keybinds.lua`（快捷键）/ `execs.lua`（hyprland.start 启动项）/ `services/`（hypridle 等）/ `shellOverrides/main.lua`
  - `scripts/` —— `mask_kded6.sh`、`gamepad-active.py`、`snip_to_search.sh`、`launch_first_available.sh`、`switchfloatfocus.sh`、`fuzzel-emoji.sh` 等
  - `custom/` —— 自维护补充（不会被更新覆盖）
- `hypridle.conf` / `hyprlock.conf` —— 仍用 conf；**没有** `hyprland.conf`（入口是 lua）
- `dots/.config/kded5rc` → `~/.config/kded5rc`：禁 kded6 `devicenotifications`（kded6 读这个文件名，不是 `kded6rc`）

### Quickshell/II shell（`dots/.config/quickshell/ii/`）
- 入口 `shell.qml`（`qs -c ii` 加载），`settings.qml`（设置应用），`welcome.qml`
- `services/` —— Singleton 服务（`pragma Singleton`）：
  - 系统类：Audio/Brightness/Cliphist/Battery/Network/BluetoothStatus/Wallpapers/Notifications/Idle/Updates/Weather/HyprlandData/HyprlandXkb/Hyprsunset
  - 定制类：`Lyrics.qml`（歌词门面）、`SPlayer.qml`（SPlayer-Next 后端）、`Holidays.qml`（节假日）、`TrayService.qml`（托盘 pin 逻辑）、`MprisController.qml`、`ResourceUsage.qml`、`ClashVerge.qml`（Clash Verge Rev TUN/系统代理）、`OplusBuds3.qml`（OnePlus Buds 3 控制通道）
- `modules/`：
  - `common/` —— 共享基础：`Config.qml`（配置定义 JsonObject）、`Directories.qml`（路径，带 file://）、`Appearance.qml`（主题/颜色/字体）、`functions/`（FileUtils、LyricSync 等）、`widgets/`（含 `SyncedLyricText`）、`panels/`（lock 等）
  - `ii/` —— 主面板族：`bar/`（顶栏，含 Media/SysTray/Workspaces/Resources 等）、`sidebarLeft/`、`sidebarRight/`（日历/节假日）、`overview/`（搜索框+emoji）、`overlay/`（截图/录屏区域）、`recordingStatus/`、`mediaControls/`、`background/` 等
  - `settings/` —— 设置页（BarConfig/GeneralConfig/InterfaceConfig）+ `settings/system/`（Wifi/Bluetooth/Monitor/KDE/PipewireEq/Sound）
  - `waffle/` —— 另一个面板族（可切换）
- `translations/zh_CN.json` —— 中文翻译（新 key 追加到文件末尾，勿 `sorted()` 重排）
- `assets/`、`defaults/`、`scripts/`（含 `launch-detached-qs.sh`：清 qs crash 环境变量后再 `qs -p` 开设置/欢迎页）

## 接口信息

### qs IPC（`qs -c ii ipc call <target> <func> [args]`）
按 `IpcHandler.target` 划分：
- `bar`、`search`（Overview 搜索框）、`cheatsheet`、`overlay`、`region`（截图/录屏选区）、`recording`（录制指示器状态 `recording status <type|none>`）、`mediaControls`、`osdVolume`、`osk`、`sidebarLeft`、`sidebarRight`、`session`、`screenTranslator`、`wallpaperSelector`、`lock`、`theme`、`cliphistService`、`brightness`、`mpris`（pauseAll/playPause/previous/next）、`wallpapers`、`panelFamily`
- 面板懒加载：未打开时 hyprctl layers 看不到，先触发再验证
- 设置/欢迎页：`~/.config/quickshell/ii/scripts/launch-detached-qs.sh <qml>`（必须 unset `__QUICKSHELL_CRASH_*`，否则 `qs -p` 会被当成 crash relaunch 去加载 `shell.qml`）

### SPlayer-Next 歌词 API（`services/SPlayer.qml`）
- 端口 `14558`，默认 `127.0.0.1`，需在 SPlayer 设置开启 externalApi
- `GET /api/now-playing` → `{track:{id,title,artists[]}, position, playing, lyricAvailable}`
- `GET /api/status` → `{state, position(ms), duration}`
- `GET /api/lyrics` → `{lyric:[{words:[{word,startTime,endTime}], startTime, endTime, isBG}]}`
- `POST /api/play|pause|stop|next|prev|seek|volume`；`WS /ws` 事件推送

### SNI 系统托盘
- **当前**：qs 自建 `org.kde.StatusNotifierWatcher`（`StatusNotifierWatcher::instance()`）；`mask_kded6.sh` 阻止 kded6 抢占
- 验证：`busctl --user status org.kde.StatusNotifierWatcher | grep PID=` 应对上 qs；items：`busctl --user get-property org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems`

### OnePlus Buds 3 设备控制（本项目定制）
- 目前只匹配规范化名称 `OnePlus Buds 3`；入口位于蓝牙设置的对应已保存设备行，耳机未连接时入口禁用。控制 UI 在 `settings/system/OplusBuds3Config.qml`，通过 `Loader` 按需加载，不与通用蓝牙选项混排
- `services/OplusBuds3.qml` 在开启顶栏蓝牙电量或专属页面打开时在后台与设备通信维护电量与控制通道，退出或关闭时自动释放连接与 RFCOMM 通道；设备地址从 Quickshell 蓝牙模型动态取得，不写入配置
- `scripts/bluetooth/oplus-buds3-bridge.c` 使用 BlueZ RFCOMM 和耳机私有 SPP 帧，自动探测通道；启动脚本用 `cc` + `libbluetooth` 按需编译到 `~/.cache/quickshell/helpers/`（Arch 依赖 `base-devel`、`bluez-libs`）
- 协议字段按 `Osilvfe/OppoPodsManager-linux` 的 OnePlus Buds 3（产品 ID `063C14`）实现：电量、降噪/通透、EQ、空间音频、游戏模式/音效、双设备和佩戴检测。游戏音效与空间音频、非默认 EQ 的互斥在桥接器中同步处理

### 快捷键（`keybinds.lua`）
- `SUPER` 单按=搜索框 toggle（`SUPER_L`/`SUPER_R`，`release=true`）；`SUPER+Tab`=**scrolloverview 插件**概览（不是 qs Overview）；`SUPER+V` 剪贴板；`SUPER+Period` emoji；`SUPER+SHIFT+S` 截图工具菜单；`SUPER+SHIFT+A` 图像搜索；`SUPER+SHIFT+X` OCR；`Print` 全屏截图 / `CTRL+Print` 存文件

### 常用脚本
- `hyprland/scripts/mask_kded6.sh` —— 非 KDE：假 D-Bus service `Exec=/bin/false` + `systemctl --user mask plasma-kded6.service`；`XDG_CURRENT_DESKTOP=KDE` 时执行则还原。安装 `3.files-exp.sh` 会跑一次
- `hyprland/scripts/gamepad-active.py` —— 手柄检测（hypridle 用）
- `quickshell/ii/scripts/launch-detached-qs.sh` —— 开 settings/welcome
- `quickshell/ii/scripts/bluetooth/oplus-buds3-bridge.sh` —— 按需编译并启动 OnePlus Buds 3 原生 RFCOMM 桥接器
- `fuzzel-emoji.sh`、`snip_to_search.sh`、`launch_first_available.sh`、`switchfloatfocus.sh`

## 同步与发布
- 修改 `dots/` 下文件后，手动 `cp -f <源> <目标路径>` 到 `~/.config/` 对应路径（无自动同步）
- **`cp -r` 到已存在目录不会覆盖子文件**——同步后用 `grep`/`diff` 验证部署内容而非只看文件存在
- 提交前检查 `git status`，只提交本仓库文件；改 qs 组件后需清 qmlcache 重启（见下）

## 上游合并记录

早期整支 PR：`git fetch <pr-remote> <branch>` + `git merge --no-commit`（勿 cherry-pick 中间提交）。`record.sh` / hypridle / bar 分叉之后改为对照 PR diff 作本地补丁，**勿再整支 merge 上游分支**。

### 整支 merge
- **#3484** `eea9a660` — songrec：`recognize-music.sh` `"matches": [` → `"track":`（紧凑 JSON）
- **#3497** `af766d4d` — 设置侧栏分层（`iiPages` + Connectivity/Monitor/KDE）；`settings/system/` 有 Wifi/Bluetooth/Monitor/KDE，**未留 VpnConfig**。合并带出的 WifiDialog 孤儿 `visible` 已在 `83125c42` 修掉
- **#3135** `c7639efb` — Android 16 快捷设置弹窗卡片化。已跟进：设备色 input=primary / audio=tertiary / 其他=secondary；蓝牙按名称/MAC 分组；提示字号 `pixelSize.small`；分区头 `Layout.leftMargin: 12`（`399352bd`）；底部 `WindowDialogButtonRow` `margins:-8` + 各框 `Layout.margins: 4`

### 本地补丁 · bugfix（`c7c5790c`）
- **#3517** 翻译复制按钮挂 `ButtonGroup.groupData`（不是 `actions.data`）
- **#3518** 待办 `listBottomPadding`，最后一项不被 FAB 挡住
- **#3465** AI 代码块未知语言不再崩
- **#3587** 录屏 `yuvj420p`（**不合**上游 `-t`，本仓库禁止 `-t`）
- **#3592** `HyprlandXkb` 只跟主键盘 layout（避开 fcitx 虚拟设备）
- **#3500** Wi-Fi `nmcli monitor` 连发不再重开还在跑的 Process
- **#3585** 开着 VPN 不再显示 Wi-Fi 警告图标
- **#3479** 关右侧栏后角触发不会马上再打开
- **#3451** 启动器 `Terminal=true` 按参数转义，不 `join(' ')` 整串给 `-e`
- **#3560** `windowtitle` 只刷新 client 列表
- **#3526** 通知堆积时整组关闭不再打满 CPU
- **#3612** Overview 剪贴板读取 `Cliphist.currentEntryText` 避免 Wayland 10-15s 同步读超时；`AppSearch` 150ms 聚合防抖
- **#3634** 蓝牙设备 1000ms 排序节流 + `areDeviceListsEqual` 浅比对防 CPU 100%；`expandedAddress` 维持展开状态；移除夜间模式误触发扫描
- **#3622** `applycolor.sh` 仅对真实控制终端 pty 发送 OSC 转义序列
- **#3627** `applycolor.sh` / `switchwall.sh` 临时文件原子替换避免损坏终端配置与 scss；`pgrep -x kitty` 精准匹配
- **#3614** 背景天气组件温度字段 `typeof string` 守卫，避免未拉取时 TypeError
- **#3616** `KeyringStorage` 异步初次加载前的写入队列保护，防止覆盖抹除已有密钥
- **#3617** `SqueezedAnnotationStyledText` 翻译自适应尺寸增加宽度溢出检测、尺寸为 0 守卫与 resize 重新计算
- **#3599** `random_osu_wall.sh` 遭遇 Cloudflare 人机拦截时优雅降级并弹窗提示

### 本地补丁 · 功能
- **#3533** OSD/顶栏滚轮音量上限（`audio.osdMaxPercent`，默认 150；不影响键盘 `wpctl -l 1.5`）
- **#3535** 勿休眠顶栏咖啡杯（`bar.indicators.showIdleInhibitor`，默认开）
- **#3538** 顶栏蓝牙电量（`bar.indicators.showBluetoothBattery`，默认开）
- **#3581** 可选通知提示音（`sounds.notifications`，默认关）
- **#3144** Gemini `thought_signature` + 完整 `functionCall`（无设置开关）
- **#3600** 设置页自定义主题主色（复用 `switchwall.sh --color`）
- **#3598** 主题槽位：保存/恢复/删除壁纸、明暗模式、配色方案与自定义主色（10 个槽位）
- **#3546** Overview 剪贴板清除全部/筛选结果按钮与空状态提示
- **#3307** 应用启动器支持 `.desktop` 关键词（Keywords）与通用名（GenericName）加权检索打分
- **#3480** 右侧栏 Wi-Fi 弹窗增加手动重新扫描按钮与防抖刷新
- **#3462** 锁屏界面增加媒体控制器卡片（带封面、切歌、音量与 Cava 律动频谱动效）
- **#3449** 快捷键速查表（Cheatsheet）支持按键与描述即时搜索，元素周期表高亮，优化弹窗打开延迟
- **#3621** 设置应用界面页支持调节活动窗口边框粗细（`general:border_size`）并修复 SpinBox 绑定自循环
- **以太网（RJ45）设置支持**：网络设置页面（`WifiConfig.qml`）整合以太网配置与状态展示卡片（`EthernetSection.qml`），通过 `scripts/network/ethernet-info.py` 动态探测有线网卡硬件信息、网线插入/载波状态、协商速率、MAC/IP/网关/DNS，支持快速一键复制、自动连接开关与手动连接/断开，设置应用侧边栏统一升级为“网络”（Network）并支持 `QS_SETTINGS_TARGET=ethernet` 自动跳转
- **顶栏耳机双耳电量支持**：在顶栏蓝牙电量指示器中，针对 TWS 蓝牙耳机（如 OnePlus Buds 3）获取并显示左右耳与充电盒独立电量；支持配置默认显示双耳中电量较低的一只耳（`bar.indicators.bluetoothBatteryLowestEarbud`，默认开启），图标自动切换为专属 `earbuds` 符号；鼠标悬停提示弹窗展示各单耳及耳机盒精确电量与充电状态

### 本地修复（无对应 PR）
- **`StyledToolTip`** 引入 `HoverHandler` 聚合 `parent?.hovered`、`parent?.containsMouse` 与 `hoverHandler.hovered`，修复父级容器（如 `ConfigSpinBox`/`MouseArea`）无 `hovered` 属性时 ToolTip 默认常驻显示
- **`c2de877c`** 设置/欢迎走 `launch-detached-qs.sh`，避免 `__QUICKSHELL_CRASH_*` 让 `qs -p` 再开一根顶栏
- **`ac34923b`** `notifications.forceMonitor`（上游 #3593）；SearchItem `entry?.`；关夜间模式停 hyprsunset；HyprlandData debounce layout；`XDG_DATA_DIRS` 去重；锁屏 Caps Lock；亮度保底 5%；封面 URL 清空时保留上一张
- **`399352bd`** 农历位运算、SPlayer 空闲退避、playerctld 始终过滤、蓝牙分组

## 踩坑记录

### Quickshell/II 开发经验
- **qmlcache 缓存**：`~/.cache/quickshell/qmlcache/` 缓存 import 模块编译结果，**自动 reload 不会失效**。修改 import 的组件后必须 `rm -rf ~/.cache/quickshell/qmlcache` + 重启 qs（`pkill -x qs; nohup qs -c ii &`）
- **pgrep 自匹配**：`bash -c` 里 `pgrep -f 'pattern'` 匹配 bash 自身；用 `pgrep -x <进程名>`（精确匹配）
- **组件 import 归属**：`PanelWindow`/`GlobalShortcut`=`Quickshell`(+`Quickshell.Hyprland`)；`WlrLayershell`=`Quickshell.Wayland`；`IpcHandler`=`Quickshell.Io`；`Translation`=`qs.services`
- **Repeater 限制**：JS 对象数组作 model 不创建 delegate（用 ListModel/字符串数组）；QtQuick.Controls 组件作 delegate 动态创建失败（用 Rectangle+MouseArea）
- **自绘组件必须显式 implicitWidth/implicitHeight**
- **`TypeError: Property 'xxx' is not a function`**：多半是 qmlcache 损坏元对象，删缓存重启
- **图标**：Material 图标用 `MaterialSymbol`；`Text+"Material Symbols Rounded"` 在 Repeater delegate 渲染失败
- **层级/命中**：PanelWindow 子项超出父几何时父 z 保护失效——浮层须独立窗口或留在父几何内
- **Singleton 懒加载**：`pragma Singleton` 只在被引用时实例化，`Component.onCompleted` 不在 qs 启动时执行——预拉取须从顶层常驻组件（`GlobalStates.qml`）显式调用
- **Process 信号**：`onExited`（非 `onProcessExited`）；stdout 用 `StdioCollector.onStreamFinished`
- **JS 类型注解坑**：`function foo(x: number): var` 被信号处理器调用报 `should be coerced to void`——去掉注解
- **文件读写**：读 `FileView.text()`、写 `setText()`，`path` 需 `Qt.resolvedUrl(...)`；`FileUtils` 只有路径函数。**`Directories.state` 等带 `file://` 前缀**，实际路径须 `FileUtils.trimFileProtocol(...)`，否则 mkdir/setText 会在 cwd 下建 `file:` 目录
- **设置面板**：`ConfigSwitch`/`ConfigSpinBox`/`ConfigSlider`（`textWidth` 默认 120，长文字挤压滑块需调大）/`MaterialTextArea`/`ContentSection`/`ContentRow`（`uniform:true` 对齐，奇数补 `Item{Layout.fillWidth:true}`）。新文本补 `translations/zh_CN.json`（保持原 key 顺序追加，勿 sorted() 重排）
- **设置项遗漏检查**：Config.qml JsonObject 定义 ≠ 设置 UI 暴露项，新增要确认有开关

### 节假日显示（本项目定制）
- **数据源双轨**（节日当天不要用农历公式反推公历——用 Nager 的精确日期）：
  - `Nager.Date`（`date.nager.at/api/v3/PublicHolidays/{year}/CN`）→ 节日当天
  - `NateScarlet/holiday-cn`（GitHub 静态 `{year}.json`）→ 放假/调休（isOffDay）
  - 合并缓存 `~/.local/state/quickshell/holidays/{year}.json`（离线可用）
- **农历格子**：`calendar_layout.js` 用经典 `lunarInfo` 位（闰月 `info & 0xf`，月大小 `0x10000 >> m`）。**不要**改成 `1 << (3 + m)`（曾把 2026-02-17 春节显示成腊月十九，已在 `399352bd` 修好）
- **显示规则**：节日当天=日期下节日名+右上角"休"；放假="休"（colPrimary）；调休补班="班"（colError 红）
- `BottomWidgetGroup.qml` 展开 `implicitHeight: 430`（内容变高会被 clip 裁掉）

### 录制/音频体系（本项目定制）
- **截图菜单**（SUPER+SHIFT+S → quickshell:regionScreenshot）：选区工具栏含 取色器/录屏/录GIF/录麦克风/录系统声音
- **录屏**：`record.sh`（--region/--fullscreen/--window；--audio-src 可多个混音；--gif 走 ffmpeg 转）。**勿用 `-t`**；停止 `pkill -INT wf-recorder`（SIGINT 优雅封装）。区域录制先发 startRecording 信号（RegionSelector 定时器接管）再 dismiss()；延迟 600ms 启动（销毁冻结帧 ScreencopyView）；录制模式只允许拖拽框选；wf-recorder --geometry 用**全局逻辑坐标**（regionX+monitorOffsetX，勿乘 monitorScale）
- **录音**：麦克风 `pw-record`；系统声音 **`parec --device=$(pactl get-default-sink).monitor`**（pw-record --target 不可靠）。存 `~/Music`（mic_/system_ 前缀）
- **录制指示器**：状态由 IPC 驱动（`qs -c ii ipc call recording status <type|none>`），无文件轮询；`nowMs` + Timer，且 **`running: recordingActive`**（空闲不要空转）
- **蓝牙**：HFP（8kHz）导致无声/静音，wireplumber 配置 `bluez5.headset-roles = [ ]` 禁用；重连需手动
- **UI 组件**：`StyledComboBox`/`ConfigSwitch`/`IconToolbarButton`/`IconAndTextToolbarButton`/`Toolbar`

### PipeWire 分设备 EQ（本项目定制）
- `services/PipewireEq.qml` + `modules/settings/system/PipewireEqConfig.qml` 提供分设备 EQ 管理；后端为 `scripts/audio/pipewire-eq.py`
- 使用 PipeWire 节点的内部 `audioconvert.filter-graph.N` 将滤镜直接附加到物理 `Audio/Sink`，按稳定的 `node.name` 精确匹配，不创建新的虚拟默认 sink
- 配置、运行时节点序列号与生成的 profile 位于 `~/.config/illogical-impulse/pipewire-eq/`；不生成 WirePlumber 片段，避免重连时持久规则与 Quickshell reconcile 重复挂载 graph
- 支持标准 AutoEQ `ParametricEQ.txt`（PipeWire `param_eq`，保留 Preamp）和无表头频率/增益二列曲线（转最小相位 FIR，PipeWire `convolver`）
- FIR 同时生成 44.1/48/96/192 kHz，convolver 按 graph rate 选择最近文件；正增益曲线自动整体下移并留 0.2 dB 余量
- 导入默认不启用；启停通过设备节点 `Props` 的 `audioconvert.filter-graph.7` 热加载/卸载，可连续播放做 A/B，不重启 WirePlumber；`GlobalStates` 常驻预加载服务，设备重连后按持久状态自动 reconcile
- PipeWire 1.6 的 `audioconvert.filter-graph.N` 是只写运行时命令，不会由 `enum-params Props` 回显；管理器以 `object.serial` + graph 哈希记录本次节点是否成功下发，序列号变化时重新挂载
- JamesDSP 支持已移除；PipeWire 分设备 EQ 是仓库内唯一的 EQ 集成
- 曲线界面：`modules/settings/system/EqCurveView.qml` 提供 20 Hz – 20 kHz 对数频响曲线展示与自适应 dB 刻度；后端 `pipewire-eq.py` 计算并缓存 200 点对数采样（FIR 对数插值/WAV 重构；参数 EQ 闭式双线性解析响应，数值稳定无抵消）；支持动态鼠标探针、0 dB 基准线、各段滤镜节点与参数芯片列表，随设备启用/旁路状态同步呈现主色与半透明填充渐变
- 声音设置面板：`modules/settings/system/SoundConfig.qml` 提供系统级声音管理（物理输入/输出设备选择、主音量与麦克风增益、声道与提示音测试、应用音量混音器、系统提示音开关与主题选择、防爆音与音量保护）；与 `PipewireEqConfig.qml` 作为二级页面挂载在设置应用的 `Audio` 分类下

### Hypridle
- 关屏后挂起死锁——已改**不黑屏直接挂起**（无 DPMS off listener）；唤醒 `after_sleep_cmd`+`on-resume` 里 `hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'`
- 手柄检测 `gamepad-active.py`（EVIOCGBIT 并行 select，避免 pgrep 自匹配/窗口耗尽）

### II Overview / 搜索框（本项目定制）
- **SUPER 单按**：`keybinds.lua` 里 `SUPER_L` 绑 `quickshell:searchToggle`（`release=true`）——按下松开后 toggle
- **搜索框**：`Overview.qml` `width: Math.min(680, panelWindow.width-80)`，竖直位置 `y: height*0.18`；`SearchBar.qml` `implicitHeight: 52`+`font.pixelSize.large`
- **开关动画**：compositor 对 `quickshell:overview` 仍 `no_anim`（避免叠两套）。QS 侧 `keepSearchMounted` 关后挂 ~180ms，透明度 + scale(0.94) + 轻微上浮；进 280ms `emphasizedDecel` / 出 160ms `emphasizedAccel`
- **emoji 面板**：`SearchWidget.qml` 有 `emojiMode`（`searchingText.startsWith(prefix.emojis)`）+`emojiGrid`（GridView）；`Emojis.qml` word-based matching（空搜全返、每词须出现、slice 50）
- **模块恢复**：从 `upstream/main` 恢复 QML 因版本不兼容不工作，用**本地历史版本**（`git show <commit^>:<path>`）；Overview 删除分两步（`4ec200e3`+`25899354`），恢复版本要匹配
- **git revert 冲突**：保留后续功能文件（`git checkout --ours`）；revert 带出无关改动（如 persistent_workspaces）需手动排除
- **面板加载验证**：PanelLoader 懒加载，`qs -c ii ipc call search toggle` 后 `hyprctl layers | grep quickshell:overview`

### Hyprland 动画（`hyprland/general.lua`）
- speed 单位是 ds（1 = 100ms）。窗口 **开 350ms** `niriOpen`（带一点 overshoot）、**关 150ms** `niriClose`；图层开 250ms / 关 200ms（关不要比开慢）
- **工作区**：`slidevert` + 真弹簧 `niriWorkspace`（mass=1, stiffness=1000, dampening=63.2，临界阻尼，约 250ms 收住）。`hl.animation({ spring = "name" })` 时 duration 由物理决定，`speed` 只是解析器占位。贝塞尔 `niriSpring`（12% 回弹）只给 `windowsMove`，全屏竖滑不要用
- 便签本 `specialWorkspace` 同一套弹簧。OSD：`quickshell:onScreenDisplay` layer fade

### 顶栏媒体歌词（本项目定制）
- **分层**（顶栏不要直接绑某个播放器）：
  - `services/Lyrics.qml` —— 门面。约定见文件头（`lineText` / `lineWords[{word,startTime,endTime}]` / 行起止 / 播放时钟 / `isInterlude`）。新源实现约定后插入 `active`（先匹配优先）
  - `services/SPlayer.qml` —— 当前唯一后端（SPlayer-Next external API）
  - `functions/LyricSync.qml` —— 逐字时间 → 字符/像素位置，与源无关
  - `widgets/SyncedLyricText.qml` —— 显示：有时间轴且超长则 karaoke 滚（当前字约在视口 42%），否则 ghost marquee；短句居中。`FrameAnimation` 跟帧；字宽换行时预计算；滚动文本 `renderType: QtRendering`（Native 亚像素会闪）
- **SPlayer 通道**：XMLHttpRequest（参考 `Booru.qml`）。WS 事件驱动 + HTTP 兜底：
  - **WebSocket 主通道**（`services/wsclient.qml`，根类型 WebSocket）：推 `track`/`lyric`/`status`/`ended`——**不推连续 position**（`HIGH_FREQ_EVENTS` 过滤 `position`/`fftData`），`lineChange` 只在插件通道不经 WS
  - **position 本地推算**：status 事件 `setAnchor`，播放中 200ms Timer 更新 `positionMs`（karaoke 显示用 `Date.now()-anchorAt` 外推，不跟这 200ms）；WS 已连时 **8s** HTTP `/api/status` 校准（`statusPollWhenWsMs`）
  - **降级 / 退避**：WS 未连上时同一 Timer 兼拉 `/api/now-playing`；API 不可达时 `failBackoffMs` 3s→30s。HTTP 3s timeout
- **`import QtWebSockets` 深坑**：WebSocket **静态声明在 Singleton 内（或作 QtObject 子对象）永远不连接**（qml_rs 下停在 Connecting）——必须 `wsclient.qml` 以 WebSocket 为**根类型**、`Qt.createComponent` + `createObject(null)`，事件在组件内转 `SPlayer.onWsStatus/onWsMessage`；**外部 `.connect()` 与自定义 property 均不可靠**
- **同步**：跳过 isBG 选当前行，暴露 `lineText`+`lineWords`；WS `track` 切歌时清行、清 `durationMs`/`lyricAvailable`/`lineWords`，再 `loadLyrics()`。`lyricAvailable` 以 API 字段或已加载行数为准，切歌时不要无条件 `true`
- **间奏**：SPlayer API **无 intro/interlude 字段**——照抄前端 `detectInterlude`：position 落在某行 `endTime` 到下一行 `startTime-250ms` 且间隙 ≥`minInterludeGap`（默认 4000ms）；末行到 `durationMs` 同样判 outro。`isInterlude=true` 时顶栏三个 `music_note` MaterialSymbol（`♪` 在 CJK 正文会缩成小符号；Repeater+图标字体渲染失败，须静态写）
- **API 断开**：WS Error/Closed 或 HTTP 失败 → `handleApiDown` → `apiDown` + `clearAll()`
- **MPRIS `xesam:asText` 不是实时歌词标准**；无 Lyrics 源时顶栏回退 MPRIS 标题
- 调试：Media 常驻，加日志用编辑工具，勿 sed 多行替换

### MPRIS 幽灵标题（MprisController，本项目定制，深坑）
- **症状**：播放器（SPlayer/浏览器）退出后顶栏残留旧标题
- **根因 1（主因）**：`Instantiator` delegate 里 `Component.onDestruction` 触发时 **`required property modelData` 已被清空为 null**（QML 销毁时清 context property）——`trackedPlayer === modelData` 比较永远 false，死 player 引用永不清除。**修法：onCompleted 里捕获 `property MprisPlayer playerRef = modelData`，onDestruction 用 playerRef 比较**（死亡 C++ 对象的 QML wrapper 身份比较仍有效，但读其属性如 dbusName 已返回 undefined）
- **根因 2（帮凶）**：**playerctld 僵尸镜像**——playerctld 受控的最后一个 player 消失时**只发 `ActivePlayerChangeBegin("")`、不发 PropertiesChanged**（playerctl-daemon.c 源码实证），qs 里 playerctld 的 MprisPlayer 对象永久缓存旧 title + Playing 状态。**修法：`isRealPlayer` 无条件丢掉 playerctld**（即使 `filterDuplicatePlayers` 关闭）；tracking/fallback/activePlayer 全部经 `isRealPlayer`；activePlayer 用 `computeActivePlayer()` + `playersRevision`（player 出现/消失时自增，否则 fallback 死亡时绑定不重算）
- **验证**：用假 MPRIS bus（`org.mpris.MediaPlayer2.faketest`，GetAll 完整属性，playerctld 会镜像）跑几秒退出，看 tracked/active；镜像状态用 `busctl get-property org.mpris.MediaPlayer2.playerctld`

### Clash Verge Rev 图块（本项目定制）
- 替换原 Cloudflare Warp 快捷开关（类型 `clashVerge`；旧配置里的 `cloudflareWarp` 仍映射到同一图块）
- `services/ClashVerge.qml`：状态读 Mihomo HTTP。`secret` 和 `external-controller` 来自 `~/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml`（默认 `127.0.0.1:9097`）。**secret 只读配置，永不写进仓库或硬编码**
- **开关必须走 Clash Verge 托盘菜单**（`SystemTray.items` → `QsMenuOpener` → 文案匹配「系统代理」/「TUN 模式」→ `QsMenuEntry.triggered()`）。这会跑 `patch_verge` + `refresh_verge`，窗口才能同步。直接 `PATCH /configs` 或改 `verge.yaml` **不会**刷新 GUI。托盘未就绪时才 fallback HTTP/`gsettings`
- 图块单击默认开 **TUN**；再点关系统代理 + TUN。右键对话框可单独开关
- 改组件后清 qmlcache 重启 qs

### SNI 系统托盘（本项目定制，深坑）
- **架构（当前）**：**qs 自建 watcher**（vanilla quickshell，`StatusNotifierWatcher::instance()`），`mask_kded6.sh` 屏蔽 kded6——kded6 不抢 watcher
- **旧方案（已废弃）**：qs 纯 host + kded6 当 watcher（`sni-stale-cleanup.patch` + `start_sni_watcher.sh`）。patch 已从 PKGBUILD 删除，仓库里也没有该脚本
- **应用行为差异**：fcitx5 监听 watcher 变化、自动重注册（新 bus name）→ 可能累积重复残留。QQ/微信会随 watcher 重建重新挂上，重启 qs 不必重开应用
- **`devicenotifications` 崩溃**：kded6 纯 Hyprland 下该模块 `wl_proxy_get_version` 崩溃 → 仓库 `dots/.config/kded5rc` `[Module-devicenotifications] autoload=false`。**kded6 读 `kded5rc` 不是 `kded6rc`**
- **验证**：`busctl --user status org.kde.StatusNotifierWatcher | grep PID=` 看是否为 qs

### hyprpm / Hyprland 插件
- **编译失败排查**：先看 `hyprpm update -v` 的 g++ 报错。头文件 API 不匹配（`keybinds/Resolver.hpp`、`groupsLocked`、`m_bindInvocationDepth`）说明插件追新但 Hyprland 旧——手动 `hyprpm add <url> <git rev>` 锁兼容 commit
- **兼容性验证**：clone 后 `pkg-config --cflags hyprland`（指向 `/var/cache/hyprpm/*/headersRoot`）本地 `make` 验证
- **hyprpm 权限坑**：`/var/cache/hyprpm/{user}/` 残留 root 文件报 cache dir/plugin state 错误——`sudo chown -R <user>`；add 的 install 走 sudo（非交互失败）
- **加载失败 `/proc/self/exe`**：二进制是 `(deleted)`（包更新未重启）时插件解析路径失败——**重启 Hyprland**
- **scrolloverview**：安装脚本 / README 使用 `hyprpm add … origin/new-release`。若 `hyprpm update -v` 因头文件 API 不匹配失败，再锁兼容 commit（历史上 0.56 旧 API 用过 `0972b6b`，不要默认当成当前必锁版本）
- **插件 fallback**：`general.lua` 里 `hl.plugin.xxx` 必须包 `if hl.plugin.xxx then`（含 config 段），否则 nil index 崩溃
- **光标**：Wayland=`hyprctl setcursor <theme> <size>`（24）；XWayland=`XCURSOR_SIZE` env（48）

### 其他
- 系统声音录制时若默认输出是蓝牙耳机，确保 A2DP 模式（HFP 已禁用）
