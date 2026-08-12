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
  - `variables.lua` / `env.lua`（环境变量：XCURSOR_SIZE、OZONE 等）/ `colors.lua`（色板）/ `general.lua`（通用+动画+插件守卫）/ `rules.lua`（窗口规则+XWayland no_blur）/ `keybinds.lua`（快捷键）/ `execs.lua`（hyprland.start 启动项）/ `services.lua`（hypridle 等服务）/ `shellOverrides.lua`
  - `scripts/` —— shell 脚本（截图、录音、SNI watcher 等）
  - `custom/` —— 自维护补充
- `hyprland.conf` / `hypridle.conf` / `hyprlock.conf` —— 部分老式配置仍保留

### Quickshell/II shell（`dots/.config/quickshell/ii/`）
- 入口 `shell.qml`（`qs -c ii` 加载），`settings.qml`（设置应用），`welcome.qml`
- `services/` —— Singleton 服务（`pragma Singleton`）：
  - 系统类：Audio/Brightness/Cliphist/Battery/Network/Wallpapers/Notifications/Idle/Updates/Weather
  - 定制类：`SPlayer.qml`（歌词）、`Holidays.qml`（节假日）、`TrayService.qml`（托盘 pin 逻辑）、`MprisController.qml`、`ResourceUsage.qml`
- `modules/`：
  - `common/` —— 共享基础：`Config.qml`（配置定义 JsonObject）、`Directories.qml`（路径，带 file://）、`Appearance.qml`（主题/颜色/字体）、`functions/FileUtils.qml`、`widgets/`（通用组件）、`panels/`（lock 等）
  - `ii/` —— 主面板族：`bar/`（顶栏，含 Media/SysTray/Workspaces/Resources 等）、`sidebarLeft/`、`sidebarRight/`（日历/节假日）、`overview/`（搜索框+emoji）、`overlay/`（截图/录屏区域）、`recordingStatus/`、`mediaControls/`、`background/` 等
  - `settings/` —— 设置面板页面（BarConfig/GeneralConfig/InterfaceConfig 等）
  - `waffle/` —— 另一个面板族（可切换）
- `translations/zh_CN.json` —— 中文翻译
- `assets/`、`defaults/`、`scripts/`（shell 内脚本）

## 接口信息

### qs IPC（`qs -c ii ipc call <target> <func> [args]`）
按 `IpcHandler.target` 划分：
- `bar`、`search`（Overview 搜索框）、`cheatsheet`、`overlay`、`region`（截图/录屏选区）、`recording`（录制指示器状态 `recording status <type|none>`）、`mediaControls`、`osdVolume`、`osk`、`sidebarLeft`、`sidebarRight`、`session`、`screenTranslator`、`wallpaperSelector`、`lock`、`theme`、`cliphistService`、`brightness`、`mpris`（pauseAll/playPause/previous/next）、`wallpapers`
- 面板懒加载：未打开时 hyprctl layers 看不到，先触发再验证

### SPlayer-Next 歌词 API（`services/SPlayer.qml`）
- 端口 `14558`，默认 `127.0.0.1`，需在 SPlayer 设置开启 externalApi
- `GET /api/now-playing` → `{track:{id,title,artists[]}, position, playing, lyricAvailable}`
- `GET /api/status` → `{state, position(ms), duration}`
- `GET /api/lyrics` → `{lyric:[{words:[{word,startTime,endTime}], startTime, endTime, isBG}]}`
- `POST /api/play|pause|stop|next|prev|seek|volume`；`WS /ws` 事件推送

### SNI 系统托盘
- `org.kde.StatusNotifierWatcher`（kded6 持有）← item 注册；qs 作 host 显示
- 验证命令：`busctl --user get-property org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems`；每个 item `busctl --user status <bus> | grep PID=`

### 快捷键（`keybinds.lua`）
- `SUPER` 单按=搜索框 toggle（release 触发）；`SUPER+Tab` 概览；`SUPER+V` 剪贴板；`SUPER+Period` emoji；`SUPER+SHIFT+S` 截图工具菜单；`SUPER+SHIFT+A` 图像搜索；`SUPER+SHIFT+X` OCR；`Print` 全屏截图 / `CTRL+Print` 存文件

### 常用脚本（`hyprland/scripts/`）
- `mask_kded6.sh` —— 屏蔽 kded6 抢 SNI watcher（qs 当 watcher；安装时执行一次，KDE 会话自动还原）
- `gamepad-active.py` —— 手柄检测（hypridle 用）
- `fuzzel-emoji.sh`、`snip_to_search.sh`、`launch_first_available.sh`、`switchfloatfocus.sh`

## 同步与发布
- 修改 `dots/` 下文件后，手动 `cp -f <源> <目标路径>` 到 `~/.config/` 对应路径（无自动同步）
- **`cp -r` 到已存在目录不会覆盖子文件**——同步后用 `grep`/`diff` 验证部署内容而非只看文件存在
- 提交前检查 `git status`，只提交本仓库文件；改 qs 组件后需清 qmlcache 重启（见下）

## 上游合并记录
从 end-4/dots-hyprland 合并进本仓库的 PR（用 `git fetch <pr-remote> <branch>` + `git merge --no-commit` 合入，勿逐个 cherry-pick 中间提交）：
- **#3484**（`eea9a660`）— songrec 音乐识别：`recognize-music.sh` 匹配 `"matches": [`（带空格）→ `"track":`，修紧凑 JSON 识别静默失败
- **#3497**（`af766d4d`）— 设置侧栏：settings.qml `pages`→`iiPages` + `categories` 分层（illogical-impulse/Connectivity/Monitor/KDE），新增 `modules/settings/system/`（WifiConfig/BluetoothConfig/VpnConfig/MonitorConfig/KdeConfig 等 7 页）+ SettingsHome + NavigationRailButton 扩展 + illogical-impulse-symbolic.svg
- **#3135**（`c7639efb`）— Android 16 风格快捷设置弹窗：蓝牙/夜间/音量/WiFi 对话框卡片化（`Section` 组件，colSurfaceContainerHighest），Appearance 加 `expressiveTitle`，WindowDialog 背景改 colLayer2Base；含 end-4 审查改进意见（见下）
- 修复 #3497 合并带出的上游 bug：WifiDialog.qml 删 WindowDialogSeparator 残留孤儿 `visible` 行导致 QML 语法错误（`83125c42`）

### #3135 待改善（end-4 意见，未做）
- 蓝牙对话框提示文字 `pixelSize.smaller`（13px）过小 → 应调大
- 蓝牙设备按 Gmail 式分组（可识别名称组 / MAC 地址组），参考 `waffle/startMenu/searchPage/SearchResults.qml`
- 分区头左 padding 对齐分区圆角
- 底部按钮 padding 收紧（WindowDialogButtonRow `margins:-8` + 各框 `margins:4`）
- 设备颜色已实现（Discussion #3133 结论）：input=primary、audio=tertiary、其他=secondary（BluetoothDeviceItem.qml:45-47）

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
- **数据源双轨**（勿用农历公式推算节日当天——`calendar_layout.js` 农历换算有 bug，2026-02-17 算成腊月十九）：
  - `Nager.Date`（`date.nager.at/api/v3/PublicHolidays/{year}/CN`）→ 节日当天精确日期
  - `NateScarlet/holiday-cn`（GitHub 静态 `{year}.json`）→ 放假/调休（isOffDay）
  - 合并缓存 `~/.local/state/quickshell/holidays/{year}.json`（离线可用）
- **显示规则**：节日当天=日期下节日名+右上角"休"；放假="休"（colPrimary）；调休补班="班"（colError 红）
- `BottomWidgetGroup.qml` 展开 `implicitHeight: 430`（原 350，内容变高会被 clip 裁掉）

### 录制/音频体系（本项目定制）
- **截图菜单**（SUPER+SHIFT+S → quickshell:regionScreenshot）：选区工具栏含 取色器/录屏/录GIF/录麦克风/录系统声音
- **录屏**：`record.sh`（--region/--fullscreen/--window；--audio-src 可多个混音；--gif 走 ffmpeg 转）。**勿用 `-t`**；停止 `pkill -INT wf-recorder`（SIGINT 优雅封装）。区域录制先发 startRecording 信号（RegionSelector 定时器接管）再 dismiss()；延迟 600ms 启动（销毁冻结帧 ScreencopyView）；录制模式只允许拖拽框选；wf-recorder --geometry 用**全局逻辑坐标**（regionX+monitorOffsetX，勿乘 monitorScale）
- **录音**：麦克风 `pw-record`；系统声音 **`parec --device=$(pactl get-default-sink).monitor`**（pw-record --target 不可靠）。存 `~/Music`（mic_/system_ 前缀）
- **录制指示器**：状态由 IPC 驱动（`qs -c ii ipc call recording status <type|none>`），无文件轮询；计时需可变属性（nowMs+Timer）驱动，readonly 绑 Date.now() 不刷新
- **蓝牙**：HFP（8kHz）导致无声/静音，wireplumber 配置 `bluez5.headset-roles = [ ]` 禁用；重连需手动
- **UI 组件**：`StyledComboBox`/`ConfigSwitch`/`IconToolbarButton`/`IconAndTextToolbarButton`/`Toolbar`

### Hypridle
- 关屏后挂起死锁——已改**不黑屏直接挂起**（无 DPMS off listener）；唤醒 `after_sleep_cmd`+`on-resume` 里 `hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'`
- 手柄检测 `gamepad-active.py`（EVIOCGBIT 并行 select，避免 pgrep 自匹配/窗口耗尽）

### II Overview / 搜索框（本项目定制）
- **SUPER 单按**：`keybinds.lua` 里 `SUPER_L` 绑 `quickshell:searchToggle`（`release=true`）——按下松开后 toggle
- **搜索框**：`Overview.qml` `width: Math.min(680, panelWindow.width-80)`+`topMargin: height*0.18`；`SearchBar.qml` `implicitHeight: 52`+`font.pixelSize.large`
- **emoji 面板**：`SearchWidget.qml` 有 `emojiMode`（`searchingText.startsWith(prefix.emojis)`）+`emojiGrid`（GridView）；`Emojis.qml` word-based matching（空搜全返、每词须出现、slice 50）
- **模块恢复**：从 `upstream/main` 恢复 QML 因版本不兼容不工作，用**本地历史版本**（`git show <commit^>:<path>`）；Overview 删除分两步（`4ec200e3`+`25899354`），恢复版本要匹配
- **git revert 冲突**：保留后续功能文件（`git checkout --ours`）；revert 带出无关改动（JamesDSP、persistent_workspaces）需手动排除
- **面板加载验证**：PanelLoader 懒加载，`qs -c ii ipc call search toggle` 后 `hyprctl layers | grep quickshell:overview`

### 顶栏媒体歌词（本项目定制）
- **数据源**：SPlayer-Next external API，XMLHttpRequest 请求（参考 `services/Booru.qml`）。WS 事件驱动 + HTTP 兜底双轨：
  - **WebSocket 主通道**（`services/wsclient.qml`，根类型 WebSocket）：服务端推 `track`/`lyric`/`status`/`ended` 事件——切歌/歌词/播放态即时更新，**不推连续 position**（`HIGH_FREQ_EVENTS` 过滤 `position`/`fftData`），`lineChange` 只在插件通道不经 WS
  - **position 本地推算**：收到 status 事件（play/pause/seek 时带 position）`setAnchor`，播放中用 200ms Timer `anchorPos + (Date.now()-anchorAt)` 推算歌词行；1s HTTP `/api/status` 轮询校准漂移
  - **降级**：WS 不可用（只开了 HTTP）时 `nowPlayingTimer` 5s 轮询 now-playing 走旧逻辑
- **`import QtWebSockets` 深坑**：WebSocket **静态声明在 Singleton 内（或作 QtObject 子对象）永远不连接**（qml_rs 下状态停在 Connecting）——必须独立组件文件 `wsclient.qml` 以 WebSocket 为**根类型**、`Qt.createComponent` + `createObject(null)` 创建、事件在组件内部 handler 转发给 `SPlayer.onWsStatus/onWsMessage`（同目录 import 可见）；**外部 `.connect()` 与自定义 property 均不可靠**（property 会导致连接失败）
- **同步**：缓存歌词行定位当前句（跳过 isBG），输出 lineText；WS `track` 事件切歌时先清行再 `loadLyrics()` HTTP 兜底（`lyric` 事件通常随后到覆盖）
- **间奏检测**（本项目定制）：SPlayer API **无 intro/interlude 标记字段**——照抄 SPlayer 前端 `detectInterlude`（`LyricLine` 只有 startTime/endTime/words/isBG/isDuet）：position 落在某行 `endTime` 到下一行 `startTime-250ms` 之间且间隙 ≥`minInterludeGap`（默认 4000ms）即视为间奏（含首行前=前奏），`lineText` 显示 `♪ ♪ ♪`。真实歌词里只有大器乐段（如 45s gap）才触发，2-3s 行间停顿不触发
- **尾部 outro**：存 `durationMs`（status 事件/轮询带），最后一行 `endTime` → `durationMs` 的 gap ≥阈值也算间奏（蓝莲花尾部 96s 纯音乐）；无 duration 时不判
- **`♪` 渲染坑**：`♪`（U+266A）在 CJK 正文 fallback 成小符号——Media.qml 用三个 `music_note` **MaterialSymbol**（`iconSize: small` 与歌词同号）并排显示间奏指示；静态书写（Repeater delegate 图标字体渲染失败）
- **API 断开**：WS Error/Closed 或 HTTP 请求失败（非 200/onerror）→ `handleApiDown` → `apiDown` 标记 + `clearAll()`，否则顶栏残留旧歌名；`reconnectTimer` 3s 重连
- **MPRIS `xesam:asText` 不是实时歌词标准**；主流靠播放器私有 API 或本地 LRC（quickshell-sample 是 Python 抓 QQ/网易云 LRC+轮询 position）
- **marquee**（`Media.qml`）：lyricon 式 **ghost 无缝滚动**——主文本+ghost 副本（`ghostSpacing:48`），`scrollX` 从 0 线性滚到 `-(文本宽+间距)` 循环，副本顶替主文本视觉无缝；等速（duration=unit*25）；左右 14px 渐变 fading edge。**动画目标用独立属性 `scrollX`，Text.x 绑定它**（避免循环依赖）；短文本居中不滚动
- 调试：Media 是常驻组件，加日志**用 Edit 工具**，勿用 sed 多行替换（会误改文件污染部署版）

### SNI 系统托盘（本项目定制，深坑）
- **架构（当前）**：**qs 自建 watcher**（vanilla quickshell，`StatusNotifierWatcher::instance()`），`mask_kded6.sh` 手动执行一次屏蔽 kded6（假 D-Bus service `Exec=/bin/false` + `systemctl --user mask plasma-kded6.service`，KDE 会话时还原）——kded6 永不抢 watcher 角色。**注意**：qs 当 watcher 的代价是 `pkill -x qs` 重启会丢 QQ/微信（Electron 只注册一次）图标
- **旧方案（已废弃）**：qs 纯 host + kded6 当 watcher（`sni-stale-cleanup.patch` 移除了 watcher 创建 + `start_sni_watcher.sh` 拉起 kded6）。patch 已从 PKGBUILD 删除，qs 恢复原版
- **应用行为差异**：fcitx5 监听 watcher 变化、自动重注册（新 bus name）→ 可能累积重复残留；QQ/微信（Electron）只在启动时注册一次，watcher 消失永不重注册 → 图标永久丢失
- **`devicenotifications` 崩溃**：kded6 纯 Hyprland 下该模块 `wl_proxy_get_version` 崩溃 → 禁用 `~/.config/kded5rc` `[Module-devicenotifications] autoload=false`。**kded6 读 `kded5rc` 不是 `kded6rc`**（KDE 源码写死）
- **验证**：`busctl --user status org.kde.StatusNotifierWatcher | grep PID=` 看 watcher 归属；`busctl --user get-property ... RegisteredStatusNotifierItems` 看 items；每个 item `busctl --user status <bus> | grep PID=` 确认归属

### hyprpm / Hyprland 插件
- **编译失败排查**：先看 `hyprpm update -v` 的 g++ 报错。头文件 API 不匹配（`keybinds/Resolver.hpp`、`groupsLocked`、`m_bindInvocationDepth`）说明插件追新但 Hyprland 旧——手动 `hyprpm add <url> <git rev>` 锁兼容 commit
- **兼容性验证**：clone 后 `pkg-config --cflags hyprland`（指向 `/var/cache/hyprpm/*/headersRoot`）本地 `make` 验证
- **hyprpm 权限坑**：`/var/cache/hyprpm/{user}/` 残留 root 文件报 cache dir/plugin state 错误——`sudo chown -R <user>`；add 的 install 走 sudo（非交互失败）
- **加载失败 `/proc/self/exe`**：二进制是 `(deleted)`（包更新未重启）时插件解析路径失败——**重启 Hyprland**
- **scrolloverview 兼容版本**：fork 0.56 用 `0972b6b`（旧 API `KeybindManager.hpp`+`EventBus.hpp` 最后版本）；`main`/`new-release` 已切新版 API 不兼容
- **插件 fallback**：`general.lua` 里 `hl.plugin.xxx` 必须包 `if hl.plugin.xxx then`（含 config 段），否则 nil index 崩溃
- **光标**：Wayland=`hyprctl setcursor <theme> <size>`（24）；XWayland=`XCURSOR_SIZE` env（48）

### 其他
- 系统声音录制时若默认输出是蓝牙耳机，确保 A2DP 模式（HFP 已禁用）
