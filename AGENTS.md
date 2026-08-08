# AGENTS.md

本项目是基于 end-4/dots-hyprland 的 Hyprland 配置（Hyprland 0.56 Lua 配置 + Quickshell/II shell，仅 Arch Linux）。

## 同步与发布
- 修改 `dots/` 下的文件后，手动 `cp` 到 `~/.config/` 对应路径（无自动同步）
- 推送到 `origin`（Osilvfe/dots-hyprland）；`upstream` 是 end-4 原仓库（仅跟踪），`quickshell-sample` 是参考仓库（不合并）
- 提交前检查 `git status`，只提交本仓库文件

## Quickshell/II 开发经验（踩坑记录）
- **qmlcache 缓存**：`~/.cache/quickshell/qmlcache/` 缓存 import 模块的编译结果，**自动 reload 不会失效**。修改 import 的组件后必须 `rm -rf ~/.cache/quickshell/qmlcache` + 重启 qs（`pkill -x qs; nohup qs -c ii &`），否则一直加载旧代码
- **pgrep 自匹配**：`bash -c` 命令行里 `pgrep -f 'pattern'` 会匹配执行命令的 bash 自身。`[m]ic_` 技巧也会被正则匹配到字面。正确做法：`pgrep -x <进程名>`（精确匹配进程名）
- **组件 import 归属**：
  - `PanelWindow`/`GlobalShortcut`：`import Quickshell`（PanelWindow 经 `Quickshell._Window` 默认导入）+ `Quickshell.Hyprland`（GlobalShortcut）
  - `WlrLayershell`：`Quickshell.Wayland`
  - `IpcHandler`：`Quickshell.Io`
  - `Translation`：`import qs.services`
- **Repeater 限制**（quickshell 环境）：
  - JS 对象数组作为 model 不创建 delegate——用 `ListModel`/字符串/数字数组
  - QtQuick.Controls 组件（RippleButton 等）作 delegate 动态创建失败——用 `Rectangle + MouseArea` 或静态书写
- **自绘组件必须显式 implicitWidth/implicitHeight**（不随内容自动计算）
- **`TypeError: Property 'xxx' is not a function`**：多半是 qmlcache 损坏的元对象，删缓存重启
- **图标**：Material 图标用 `MaterialSymbol`（text 为图标名）；`Text + "Material Symbols Rounded"` 字体在 Repeater delegate 中渲染失败
- **层级/命中**：PanelWindow 子项超出父几何时，父的 z 保护不生效（会被下层 MouseArea 捕获）——浮层必须独立窗口或保持在父几何内
- **Singleton 懒加载**：`pragma Singleton` 服务只在被引用时才实例化，`Component.onCompleted` 不会在 qs 启动时执行。要在启动时预拉取，从**顶层常驻组件**（如 `GlobalStates.qml`）显式调用一次
- **Process 信号**：是 `onExited`（不是 `onProcessExited`）；用 `StdioCollector.onStreamFinished` 拿 stdout
- **JS 函数类型注解坑**：`function foo(x: number): var` 这类注解被信号处理器调用时会报 `should be coerced to void`——quickshell 环境去掉类型注解（项目内服务均无注解）
- **文件读写**：读用 `FileView`（`text()`），写用 `setText()`，`path` 需 `Qt.resolvedUrl(...)`；`FileUtils` 只有路径工具函数，无 readFile/writeFile。`onLoadFailed` 里 `FileViewError.FileNotFound` 判断文件缺失
- **设置面板**（`modules/settings/*.qml`）：`ConfigSwitch`/`ConfigSpinBox`/`ConfigSlider`（`textWidth` 默认 120，长文字会挤压滑块，需调大）/`MaterialTextArea`（文本输入）/`ContentSection`（段）/`ContentRow`（并排，`uniform:true` 两列对齐——奇数个开关补 `Item{Layout.fillWidth:true}` 占位对齐）。新文本要补 `translations/zh_CN.json`（保持原 key 顺序追加，勿用 `sorted()` 重排否则 diff 巨大）
- **设置项遗漏检查**：Config.qml 的 JsonObject 里定义的选项 ≠ 设置 UI 暴露的项。新增选项要确认在对应 Config 页面有开关，否则只能手改 JSON

## 节假日显示（本项目定制）
- **数据源双轨**（不要用农历公式推算节日当天——`calendar_layout.js` 的农历换算本身有 bug，2026-02-17 会算成腊月十九）：
  - `Nager.Date`（`date.nager.at/api/v3/PublicHolidays/{year}/CN`）→ **节日当天**（春节/端午/中秋精确日期，直接信任）
  - `NateScarlet/holiday-cn`（GitHub 静态 `{year}.json`）→ **放假/调休**标记（`isOffDay`）
  - 合并缓存 `~/.local/state/quickshell/holidays/{year}.json`（离线可用）
- **显示规则**：节日当天=日期下方节日名+右上角"休"；放假天=右上角"休"（`colPrimary`）；调休补班=右上角"班"（`colError` 红色）
- 面板高度：`BottomWidgetGroup.qml` 展开固定 `implicitHeight: 430`（原 350，加节假日/农历后内容变高会被 `clip: true` 裁掉）

## 录制/音频体系（本项目定制）
- **截图菜单**（`SUPER+SHIFT+S` → quickshell:regionScreenshot）：选区工具栏含 取色器/录屏/录GIF/录麦克风/录系统声音
- **录屏**：`record.sh`（选区走 RegionSelection / --fullscreen / --window=hyprctl activewindow；--audio-src 可多个=系统+麦克风混音；--gif 走 ffmpeg 转 mp4→gif）
  - **不要用 `-t`**（无效参数）；停止用 `pkill -INT wf-recorder`（SIGINT 优雅封装，mp4 完整可播）
  - 区域录制走 RegionSelection 覆盖层（与截图同一选区 UI）：录屏菜单"区域"→ GlobalStates.recordRegionRequest + recordRegionSystem/Mic → RegionSelector 开选区；截图菜单"GIF"按钮 → SnipAction.RecordGif 原位切换录制模式；选区确认后 **先发 startRecording 信号（RegionSelector 定时器接管）再 dismiss()**——先 dismiss 会销毁面板导致信号丢失、录制不启动；延迟 600ms 启动 record.sh --region（销毁冻结帧 ScreencopyView，避免 screencopy 会话冲突）；**录制模式只允许拖拽框选**（禁用点击选窗口/图层/内容区域，普通单击直接关选区不录制）；录制模式隐藏底部工具条/关闭按钮（Esc 取消，指示器管理停止）；wf-recorder --geometry 用**全局逻辑坐标**（regionX+monitorOffsetX，不要乘 monitorScale）
  - RegionSelection 的 `isRecording` 判定：action ∈ {Record, RecordWithSound, RecordGif}；snip() 中记录动作分支构建 recordCmd（--gif 加在 --region 后）

- **录音**：麦克风 `pw-record`（默认源）；系统声音必须用 **`parec --device=$(pactl get-default-sink).monitor`**（`pw-record --target` 不可靠，会录到默认麦克风）。保存到 `~/Music`（mic_/system_ 前缀）
- **录制指示器**（顶栏，性能指示器左侧）：状态由 **IPC 驱动**（`qs -c ii ipc call recording status <type|none>`，脚本调用）+ RecordingStatusHandler → GlobalStates.recordingType，无文件轮询。计时需可变属性（nowMs + Timer）驱动，readonly 绑定 Date.now() 不刷新。点击指示器停止
- **蓝牙**：HFP 模式（8kHz）导致听不到声音/录音静音。已通过 wireplumber 配置（`bluez5.headset-roles = [ ]`）禁用 HFP；蓝牙重连需手动（wireplumber 重启后不会自动注册设备，重连后正常且 HFP 消失）
- **UI 组件**：`StyledComboBox`（下拉框，设备选择同款）、`ConfigSwitch`（设置行：图标+文字+开关）、`IconToolbarButton`/`IconAndTextToolbarButton`、`Toolbar`（Material 3 胶囊）

## Hypridle
- 关屏后挂起会死锁（GPU runtime resume rpm_get_suppliers，kworker blocked）——已改为**不黑屏直接挂起**（无 DPMS off listener）
- 唤醒恢复：`after_sleep_cmd` + listener `on-resume` 里 `hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'`
- 手柄检测 `gamepad-active.py`（EVIOCGBIT 查询手柄键位，并行 select 监控，避免 pgrep 自匹配/窗口耗尽）

## 其他
- 系统声音录制时若默认输出是蓝牙耳机，确保 A2DP 模式（HFP 已禁用）
- 键盘快捷键：`Print` 全屏截图、`CTRL+Print` 保存文件、`SUPER+SHIFT+S` 工具菜单、`SUPER+SHIFT+A` 图像搜索、`SUPER+SHIFT+X` OCR

## hyprpm / Hyprland 插件
- **插件编译失败排查**：`hyprpm list` 显示 `Plugin failed to build` 时，先看 `hyprpm update -v` 的 g++ 报错。头文件 API 不匹配（`keybinds/Resolver.hpp`、`groupsLocked`、`m_bindInvocationDepth` 等新版 API）说明**插件追新但 Hyprland 版本旧**——插件仓库 `hyprpm.toml` 的 `commit_pins` 只有固定版本，git 版需手动 `hyprpm add <url> <git rev>` 锁兼容 commit
- **插件兼容性验证**：`git clone` 插件仓库后，用当前 Hyprland 头文件（`pkg-config --cflags hyprland` 已指向 `/var/cache/hyprpm/*/headersRoot`）本地 `make` 验证，再决定锁哪个 rev
- **hyprpm 权限坑**：`/var/cache/hyprpm/{user}/` 下若残留 root 所有文件（曾提权构建），`hyprpm remove`/`update` 会报 `failed to create cache dir`/`Failed to write plugin state`——需 `sudo chown -R <user> /var/cache/hyprpm`；且 hyprpm 的 `add` install 步骤走 `sudo`，非交互终端会因要密码失败（交互运行即可）
- **插件加载失败 `/proc/self/exe`**：若运行中的 Hyprland 二进制是 `(deleted)`（包更新后未重启，`readlink /proc/<pid>/exe` 可见），插件 API 解析自身路径失败——**重启 Hyprland** 让新二进制生效
- **scrolloverview 兼容版本**：fork 0.56 用 `0972b6b`（8/5，"support latest Hyprland renderer API"），是旧 API（`managers/KeybindManager.hpp`+`event/EventBus.hpp`）最后一个版本；`main`/`new-release` 分支均已切新版 API 不兼容
- **插件 fallback**：`general.lua` 里 `hl.plugin.xxx` 引用必须包 `if hl.plugin.xxx then`（含 config 段），插件未加载时 else 会 `attempt to index a nil value` 导致 config 解析失败
- **光标**：Wayland 光标= `hyprctl setcursor <theme> <size>`（当前 24）；XWayland 光标= `XCURSOR_SIZE` env（当前 48，XWayland 程序读这个）
