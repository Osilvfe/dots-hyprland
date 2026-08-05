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

## 录制/音频体系（本项目定制）
- **截图菜单**（`SUPER+SHIFT+S` → quickshell:regionScreenshot）：选区工具栏含 取色器/录屏/录GIF/录麦克风/录系统声音
- **录屏**：`record.sh`（slurp 选区 / --fullscreen / --window=hyprctl activewindow；--audio-src 可多个=系统+麦克风混音）
  - **不要用 `-t`**（无效参数）；停止用 `pkill -INT wf-recorder`（SIGINT 优雅封装，mp4 完整可播）
  - 区域录制不要走 RegionSelection 的 Record action（ScreencopyView 冻结帧与会话冲突）——直接 execDetached record.sh
- **录音**：麦克风 `pw-record`（默认源）；系统声音必须用 **`parec --device=$(pactl get-default-sink).monitor`**（`pw-record --target` 不可靠，会录到默认麦克风）。保存到 `~/Music`（mic_/system_ 前缀）
- **录制指示器**（顶栏，性能指示器左侧）：状态由 **IPC 驱动**（`qs -c ii ipc call recording status <type|none>`，脚本调用）+ RecordingStatusHandler → GlobalStates.recordingType，无文件轮询。计时需可变属性（nowMs + Timer）驱动，readonly 绑定 Date.now() 不刷新。点击指示器停止
- **蓝牙**：HFP 模式（8kHz）导致听不到声音/录音静音。已通过 `~/.config/wireplumber/wireplumber.conf.d/51-disable-hfp.conf`（`bluez5.headset-roles = [ ]`）禁用；蓝牙重连需手动（wireplumber 重启后不会自动注册设备，重连后正常且 HFP 消失）
- **UI 组件**：`StyledComboBox`（下拉框，设备选择同款）、`ConfigSwitch`（设置行：图标+文字+开关）、`IconToolbarButton`/`IconAndTextToolbarButton`、`Toolbar`（Material 3 胶囊）

## Hypridle
- 关屏后挂起会死锁（GPU runtime resume rpm_get_suppliers，kworker blocked）——已改为**不黑屏直接挂起**（无 DPMS off listener）
- 唤醒恢复：`after_sleep_cmd` + listener `on-resume` 里 `hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'`
- 手柄检测 `gamepad-active.py`（EVIOCGBIT 查询手柄键位，并行 select 监控，避免 pgrep 自匹配/窗口耗尽）

## 其他
- 系统声音录制时若默认输出是蓝牙耳机，确保 A2DP 模式（HFP 已禁用）
- 键盘快捷键：`Print` 全屏截图、`CTRL+Print` 保存文件、`SUPER+SHIFT+S` 工具菜单、`SUPER+SHIFT+A` 图像搜索、`SUPER+SHIFT+X` OCR
