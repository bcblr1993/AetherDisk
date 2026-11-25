# AetherDisk 3.1.0（视觉与交互精修）正式发布验收记录

日期：2026-11-25（Asia/Shanghai）。版本 3.1.0，构建 2026112502（Apple Silicon、macOS 14+）。

> 前一正式签名公证发行版 **3.0.0（构建 `2026112501`）** 完整公证、Ed25519、GitHub Release 及 Sparkle `2.0.0 → 3.0.0` 升级验收档案保留于 [VERIFICATION-3.0.0.md](VERIFICATION-3.0.0.md)。

## 3.1.0 精修亮点

- **智能护理维度内联快速审阅抽屉（`SmartCareView.swift`）**：为「五大护理维度」新增非嵌套「展开摘要」交互（`pillar-expand-<id>`）与 `smartcare-pillar-drawer` 就地只读核查抽屉，统一覆盖系统清理、安全保护、性能优化、应用管理、空间透镜，既保有一屏免滚动直达，也支持原位快速复核与工作台跳转。
- **空间透镜气泡地图交互缩放与径向聚焦（`BubbleLensView.swift`）**：新增 `MagnificationGesture` 双指捏合缩放与左下角悬浮毛玻璃缩放胶囊（`bubble-zoom-controls`，`85%–180%`、`bubble-zoom-out` / `bubble-zoom-reset` / `bubble-zoom-in`），同步中心锚点缩放绘制与 `hitTest` 坐标、悬停径向射线高亮及两行元数据浮窗（同时暴露实时缩放百分比给可访问性树）。
- **应用管理未用天数纯元数据透视（`Applications.swift` & `ApplicationsView.swift`）**：为 `InstalledAppItem` 补充只读 `lastUsedAt`、`unusedDays(referenceDate:)` 与向后兼容旧版解码；将应用筛选与排序升级为「久未使用」，在列表展示 `近 7 天活跃` / `约 N 天未活跃` / `未活跃 ≥ N 天` 徽章并在详情栏明确标注基于文件系统元数据只读估算（所有 `.app` 本体严格只读保护）。
- **菜单栏 `MenuBarExtra` 实时双波形与轻刷新（`PerformanceAndAssistantViews.swift`）**：在 `MenuBarHealthPopoverView` 底部内嵌 `menubar-telemetry-sparklines`（CPU 与内存实时 `TelemetrySparkline` 曲线条），每 3 秒自动只读采集一次（QA 模式自动静默以保证确定性）；全链路唯一第三方生产依赖仍为 `Sparkle 2.10.0`。

## 核心构建、单元测试与宿主机真实只读扫描

- `swift build --jobs 4 -Xswiftc -warnings-as-errors`：零警告通过。
- `swift test --jobs 4`：**122 / 122 项核心单元测试全部通过，0 失败**（耗时 `13.918` 秒），涵盖新增 `testInstalledAppUnusedDaysLastUsedAtAndLegacyJSON`、`test310StaticSafetyAndUIEnhancementInvariants` 及既有的 `AnalysisTests`、`Core2Tests`、`Core3CleanMyMacTests`、`CoreTests` 与 `SafetyAuditTests`。
- 预览打包与 CLI 版本校验：`scripts/build-preview.sh` 产出本地预览包 `outputs/AetherDisk.app`（`CFBundleShortVersionString = 3.1.0`，`CFBundleVersion = 2026112502`，`codesign --verify --deep --strict` 通过），`./outputs/AetherDisk.app/Contents/MacOS/aetherdisk-scan --version` 输出 `aetherdisk-scan 3.1.0`。
- 本机真实只读 CLI 扫描（`./outputs/AetherDisk.app/Contents/MacOS/aetherdisk-scan ~/Downloads --apps --cloud --health` 与 `--json`）：
  - `~/Downloads` 扫描：`70` 个文件、`12` 个目录、`0` 个未读取路径；已分配 `2,194,558,976` 字节（`2,143,124 KiB`），与系统 `du -xsk ~/Downloads`（`2143124`）零误差一致，逻辑大小 `2,194,383,889` 字节，耗时 `0.0056` 秒。
  - `--apps`：只读识别 `80` 款应用本体及 `18` 项疑似关联残留。
  - `--cloud`：只读识别 `iCloud Drive`（`~/Library/Mobile Documents/com~apple~CloudDocs`）1 个服务，本地驻留 `18.2 GiB`（`21,166` 个本地文件）、云端占位 `5.7 GiB`（`7,225` 个占位文件）、逻辑总计 `24.0 GiB`。
  - `--health`：`MacBookPro18,2 · 版本27.0.1（版号26A434）`，CPU `负载 16.90（10 核 · 散热正常）`，电源 `外接电源 · 100%`。

## Tart `macos27` 原生全量门禁与深浅外观验收

Tart `macos27` 独立测试夹具全套 7 组原生无障碍回归门禁 **99 / 99 项全部通过**（`outputs/qa-300/summary.json` 为 `{"status": "passed"}`）：

- `vm-function-gate.json`：13 / 13 通过。
- `vm-navigation-gate.json`：8 / 8 通过。
- `021-analysis-gate.json`：14 / 14 通过。
- `ui-style-gate.json`：10 / 10 通过。
- `v050-ui-gate.json`：13 / 13 通过。
- `v200-ui-gate.json`：14 / 14 通过。
- `v300-ui-gate.json`：27 / 27 通过（覆盖智能护理 `smartcare-pillar-drawer` 内联展开与关闭、`bubble-zoom-controls` 缩放至 `120%` 与重置 `100%`、应用管理 `app-filter-unused` / `久未使用`、系统清理按应用分组及只读云盘透视、我的杂物双时间轴与疑似重复对比、性能优化趋势图与启动项联动及设置阈值选择器）。

全套 **31 张深浅色原生实机截图** 保存在 `outputs/screenshots/310-release/`（无残留 `.scan.json`），并对 `smartcare-light.png`、`smartcare-dark.png`、`bubble-light.png`、`bubble-dark.png`、`applications-light.png` 与 `applications-dark.png` 完成视觉核查：版本状态栏正确显示 `3.1.0 · 开发预览`，五列卡片展开按钮与主跳转独立清晰，气泡缩放悬浮条排版协调，应用管理「久未使用」与活跃徽章无文字截断且深浅对比明确。

## 正式签名、Apple 公证与 Ed25519 验签（3.1.0 · 2026112502）

Developer ID Application: YanNan Chen (5984KQD4D7)。Sparkle 嵌套 XPC/Autoupdate/Updater 组件、Sparkle.framework、CLI `aetherdisk-scan` 与 `AetherDisk.app` 逐层启用 Hardened Runtime 并附带时间戳签名。

- App 公证 Accepted：`c8e99b0a-d1b3-4a7a-8dd5-bf3c4c886e79`（`outputs/releases/3.1.0-2026112502/notarization-app.json`）。
- DMG 公证 Accepted：`2c402f2b-336e-4c08-bd5c-050d51171563`（`outputs/releases/3.1.0-2026112502/notarization-dmg.json`）。
- App 与 DMG 公证票据均已 `stapler staple` 装订与 `stapler validate` 验证通过，`spctl --assess` 均为 `accepted / source=Notarized Developer ID`；只读挂载 `AetherDisk-3.1.0-arm64.dmg` 核对卷名 `AetherDisk 3.1.0`、`Applications` 软链、`安装说明.txt` 与 `Info.plist`（`3.1.0` / `2026112502` / `AetherDiskRelease = True` / `SUFeedURL = https://aethernative.com/apps/aetherdisk/appcast.xml` / `SUPublicEDKey = NtKT+Grl0IhrUwpJJb5a4Lulft66JG+GqgUhx25LD2E=`）后干净卸载。
- DMG SHA256：`dcd8d82ddfb7f8b3d36418097a1b4dfa983995de78f80b3d01089c187ba95618`（长度 `5,674,613` 字节）。
- 更新包 Ed25519 签名（`tfQyOGLK8sFpTHcTAjGEJxsxy/x4Mup+sPfpdYrhXEk8oAODtdGqjWvZgugRGZxxoe9Evbf2c2Po+RUyi7l7Bg==`）与完整签名 Feed（`u/JYjWKpQqVx3BBdAJrCObxCTAdCXPeIDcVQ2X5j4DjibiPJz+bzlVjlVGDSKlOLHhmE07O6lNkb88aUIC9qDw==`，长度 `1142`）通过公开 Ed25519 公钥 `NtKT+Grl0IhrUwpJJb5a4Lulft66JG+GqgUhx25LD2E=` 校验通过，且对 DMG 与 Feed 各篡改 1 字节均被拒绝。
- GitHub Release `v3.1.0`（https://github.com/bcblr1993/AetherDisk/releases/tag/v3.1.0）已发布正式 DMG、源码包（`AetherDisk-3.1.0-source.tar.gz`，`2,080,746` 字节，SHA256 `37fdc51036897f398ecd1dd11ebbcfff8f471ee15f2fb809834df3da2db066e0`）、`SHA256SUMS.txt`、`appcast.xml`、`notarization-app.json` 与 `notarization-dmg.json`，DMG 下载跳转返回 `HTTP/2 302 → 200`。

## 真实 Sparkle 应用内升级验收（3.0.0 → 3.1.0）与发布后清理

3.0.0 (`2026112501`) → 3.1.0 (`2026112502`) 真实 Sparkle 应用内升级端到端验收（Tart `macos27` 干净独立基线，`scripts/qa/upgrade_gate.py`）10 / 10 项全部通过：

- 线上官网 Feed `https://aethernative.com/apps/aetherdisk/appcast.xml`（官网提交 `9d449ec`）实测 SHA-256 为 `164c0e10e0a4b4bb21867fe04901d2bd4528c8c8397712e75cc631b65d3f3a97`，与本地签名清单 `outputs/releases/3.1.0-2026112502/appcast.xml` 逐字节一致。
- 3.0.0（主二进制 SHA-256 `493b50aa6f4dd682a89adfd9b145dd848e8b134f07e60e267ac01cf746ff88a3`）成功识别更新并完成下载、Ed25519 验签、替换安装与重启为 3.1.0（`2026112502`），升级后主二进制 SHA-256（`44e894a140fe7f3940edd7a4b10eee9a8925fcd1b88668fabf066a86db1ac3cc`）与正式发行包完全匹配；再次检查更新提示「您使用的就是最新版」。
- 3.0.0 历史扫描快照（`d297a08e0284e453727ead14316c8c7554dd762a10a0ceb4519b9b93039f410b`）、受保护源码与安装包（`429aa948...` / `d008fa5b...`）、自动检查更新开关（`true`）及自定义保护路径（`Developer/Safe/.build`）完整保留；3.1.0 正常加载旧版快照并在「占用变化」「文件类型」页面呈现历史对比与新版分析。
- 升级验收后 VM 内全部 QA 目录、测试偏好、扫描历史与 LaunchServices 注册均已恢复清理，`macos27` 已停止。
- 发布收尾后宿主机已按规范逐项核对清理：`.build/`（`301,980 KiB` / `295 MiB`）、`outputs/releases/3.1.0-2026112502/AetherDisk.app` 解包副本（`16,036 KiB` / `16 MiB`）、`outputs/logs/`（`108 KiB`）、`scripts/qa/__pycache__/`（`12 KiB`）及冗余旧版过程截图 `outputs/screenshots/200-release/`（`5,592 KiB`）与 `outputs/screenshots/300-release/`（`39,220 KiB`），合计释放 **`362,948 KiB`（约 `354 MiB`）**，宿主机 `/` 剩余可用空间 **`129 GiB`（`135,744,548 KiB`）**；无残留 DMG 挂载或 `.scan.json`，保留唯一正式公证 `outputs/AetherDisk.app`（`codesign` 与 `spctl` 均通过 `accepted / source=Notarized Developer ID`）、历版正式归档及当前版本正式截图 `outputs/screenshots/310-release/`（31 张）。

历史版本验收记录分别保存在 [VERIFICATION-3.0.0.md](VERIFICATION-3.0.0.md)、[VERIFICATION-2.0.0.md](VERIFICATION-2.0.0.md)、[VERIFICATION-1.0.2.md](VERIFICATION-1.0.2.md)、[VERIFICATION-1.0.1.md](VERIFICATION-1.0.1.md)、[VERIFICATION-1.0.0.md](VERIFICATION-1.0.0.md)、[VERIFICATION-0.6.0.md](VERIFICATION-0.6.0.md)、[VERIFICATION-0.5.0.md](VERIFICATION-0.5.0.md)、[VERIFICATION-0.4.0.md](VERIFICATION-0.4.0.md) 与 [VERIFICATION-0.3.0.md](VERIFICATION-0.3.0.md)。
