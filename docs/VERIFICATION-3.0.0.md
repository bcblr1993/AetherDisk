# AetherDisk 3.0.0（CleanMyMac 深度对齐重构）正式发布验收

日期：2026-11-25（Asia/Shanghai）。版本 3.0.0，构建 2026112501，Apple Silicon、macOS 14+。

## 本版重构与对齐亮点

- **CleanMyMac 5 1:1 现代舞台壳层、平滑过渡与无障碍自适应（`Theme.swift` & `ContentView.swift`）**：重构为内嵌悬浮圆角毛玻璃侧边栏（顶部「智能助手」胶囊 + 严格对齐 CleanMyMac 5 的「智能护理、系统清理、安全保护、性能优化、应用管理、我的杂物、空间透镜」七大核心模块与三大实用工具）、3D 高光渐变模块徽章（`ModuleIconBadge`）、十套专属色彩舞台光晕背景（`ModuleStagePalette` & `StageBackground`，深浅外观自适应）、左右双栏欢迎英雄舞台（`ModuleHeroStage`）、星环脉冲扫描横幅（`OrbitalScanningBanner`）及无底栏遮挡的居中悬浮发光圆形主按钮（`CircularActionOrbBar`）；新增 `DiskMotion` 统一过渡动效，全面适配 `accessibilityReduceTransparency`（侧边栏、`Surface`、`StageBackground`、`CircularActionOrbBar` 实色高对比背景与强边框降级）与 `accessibilityReduceMotion`（静默旋转扫描环、呼吸光晕及即时页面切换，QA 模式下亦支持即时切页稳定性）。
- **智能护理五列纵向卡片舞台与智能助手（`SmartCareView.swift` & `SystemHealth.swift`）**：新增旗舰主页「智能护理（Smart Care）」，一屏免滚动呈现健康指数圆环、并排五列纵向毛玻璃卡片（系统清理、安全保护、性能优化、应用管理、空间透镜）与「智能助手（Smart Assistant）」诊断抽屉，并接入 `SmartCareEngine.evaluate(..., lowSpaceThresholdGiB:)` 只读低空间预警整合（绝不重复插入或触发自动清理）。
- **安全保护只读透明审计模块（`ProtectionAudit.swift` & `ProtectionView.swift`）**：新增 100% 纯元数据只读「安全保护（Protection）」模块，分栏审计 `LaunchAgents` / `LaunchDaemons` 启动代理元数据、SSH/GPG/Keychains/Git 硬保护防线与 `Downloads` 安装包清单。
- **Space Lens 左右同屏双栏与交互式比例气泡透镜（`BubbleLens.swift`、`BubbleLensView.swift` & `OverviewView.swift`）**：采用「左目录透镜树 + 右比例气泡画布」左右同屏双栏布局，新增黄金角切线无重叠圆球排布算法 `BubbleLensLayout` 与 `BubbleLensView`（`bubble-lens-canvas`），按面积比例绘制立体球体与受保护斜纹光圈，支持悬停放大浮窗、单击选中与二次点击下钻，与旭日图、树状图、分栏树、占比条组成五维空间透视。
- **系统清理双栏审阅、按应用分组与只读云盘透视（`SuggestionsAndChangesViews.swift`、`CloudStorageView.swift`、`CloudStorage.swift`、`Applications.swift`、`ApplicationsView.swift` & `AnalysisViews.swift`）**：系统清理升级为「左分类导航 + 右明细勾选」双栏布局，支持「按应用/工具链分组」折叠透视（`RecommendationQuery.groupedByApplication`），并扩充 `~/Library/Logs/*`、`~/Library/Saved Application State/*.savedState` 及 Homebrew/Zig/sccache/ccache/JetBrains/Deno/Prisma/Windsurf 等缓存规则（自动排除应用自身目录并经 `SafetyInspector` 全量校验）；新增「云盘空间透视（`CloudStorageInspector` & `CloudStorageView`）」100% 纯元数据只读对比本地实际驻留块与 `allocated == 0 && logical > 0` 云端占位体积（绝不触发下载、绝无云端删除入口）；新增纯元数据只读「应用管理」三栏透视已装应用本体、关联缓存与疑似卸载残留线索（所有 `.app` 本体严格只读保护）。
- **我的杂物双时间轴（`modifiedAt` / `accessedAt`）与疑似重复快速对比（`DirectoryHandle.swift`、`Models.swift`、`Scanner.swift`、`Analysis.swift`、`AppModel.swift`、`AnalysisViews.swift` & `AetherDiskApp.swift`）**：在 `getattrlistbulk` 批量属性读取与 `fstatat(AT_SYMLINK_NOFOLLOW)`/`lstat` 回退路径中只读采集 `ATTR_CMN_ACCTIME`（`accessedAt`）并向父目录聚合最大值（兼容无 `"accessedAt"` 的旧版 `DiskNode` JSON）；新增 `TimeAxis`（`按修改时间` / `按访问时间`）切换、`LargeFileQuery.clutterSummary` 资产概览卡片（`媒体资产` / `安装包与归档` / `陈旧大文件`）、大文件类别徽章与双时间戳胶囊，以及 `DuplicateSizeGroup.comparisonSummary` 驱动的「疑似重复快速对比面板」（`最新副本` / `较旧副本`、`protectedCount`、`spanDays` 及仅 `快速预览 (⌘Y)` / `在 Finder 中显示` / `复制路径`，严格零删除入口）。
- **性能优化趋势图、低空间阈值提醒与启动项联动（`SystemHealth.swift`、`PerformanceAndAssistantViews.swift`、`AppModel.swift`、`AppUpdater.swift` & `AetherDiskApp.swift`）**：基于 Darwin Mach `host_statistics64`、`host_processor_info`、IOKit 电源与 `getifaddrs` 只读采集内存压力与分布、CPU 负载与散热、电源状态、网络吞吐与活跃应用；新增有界 30 点 `TelemetryHistoryBuffer` 与响应式 `TelemetrySparkline`（`cpu-sparkline`、`memory-sparkline` 及均值/峰值读数）、`LowSpaceThresholdGiB`（`10/20/50/100 GiB`）与 `LowSpaceEvaluator` 只读预警（联动 `DiskSettings` 中 `low-space-threshold-picker`、智能护理、性能优化启动盘卡片及 `MenuBarExtra` 菜单栏六宫格），以及「后台启动项详情联动」卡片（`performance-launch-link`、`performance-open-launch-items`）一键直达「安全保护 -> 启动项审计」，并提供 CLI `--apps` / `--health` / `--cloud` 参数。
- **安全边界严格不变**：唯一第三方生产依赖仍为 `Sparkle 2.10.0`；所有扫描与探测全程只读、包含隐藏目录、不跟随符号链接、不跨卷、不读取文件内容、不触发 FileProvider 云端下载；仅显式二次确认且重新校验指纹的清理计划可移入系统废纸篓，禁止永久删除、禁止自动清理、禁止清空废纸篓或强杀用户应用。

## 核心测试、静态安全审计与真实只读扫描

- `swift build --jobs 4 -Xswiftc -warnings-as-errors` 零警告通过。
- `swift test --jobs 4` 全部 **120 / 120 项核心测试通过，0 失败**（`13.480` 秒：`AnalysisTests` 38 项、`Core2Tests` 17 项、`Core3CleanMyMacTests` **17 项**、`CoreTests` 25 项、`SafetyAuditTests` 23 项）；阶段四与阶段五新增覆盖 `TelemetryHistoryBuffer` 容量淘汰/均值峰值/越界与非有限值钳位、`LowSpaceEvaluator` 与 `SmartCareEngine(..., lowSpaceThresholdGiB:)` 三级阈值差额与无重复洞察插入，以及 `Theme.swift`/`ContentView.swift`/`PerformanceAndAssistantViews.swift`/`AppUpdater.swift`/`SystemHealth.swift`/`AppModel.swift` 的源码级只读安全与 `accessibilityReduceTransparency`/`accessibilityReduceMotion` 静态审计；原有 `BubbleLensLayout`、`logs`/`savedState`/`.compiler` 规则、`CloudStorageInspector`、`RecommendationQuery.groupedByApplication`、`ApplicationInspector`、`ProtectionInspector`、`DiskScanner` `accessedAt` 采集与旧版 JSON 兼容、`LargeFileQuery.clutterSummary`、`DuplicateSizeGroup.comparisonSummary`、CLI 参数及 `testStaticSourceCodeSafetyInvariants` 全部保持通过。
- 本机真实只读扫描、疑似重复线索、云盘与健康遥测（`./outputs/AetherDisk.app/Contents/MacOS/aetherdisk-scan ~/Downloads --duplicates --cloud --health`）：
  - `--health`：`MacBookPro18,2 · 版本27.0.1（版号26A434）`，内存 `已用 37.1 GiB / 64.0 GiB（承压，压缩 16.6 GiB）`，CPU `负载 6.87（10 核 · 散热正常）`，电源 `外接电源 · 100%`。
  - `--cloud`：`iCloud Drive`（`~/Library/Mobile Documents/com~apple~CloudDocs`）1 个服务，本地驻留 `18.2 GiB`（`21,166` 个本地文件）、云端占位 `5.7 GiB`（`7,225` 个占位文件）、逻辑总计 `24.0 GiB`。
  - `~/Downloads` 扫描：`70` 个文件、`12` 个目录、`0` 个未读取路径、已分配 `2,144,136 KiB`（`2,195,595,264` 字节，逻辑大小 `2,194,383,889` 字节），与系统 `du -xsk ~/Downloads`（`2144136`）逐 KiB 精确一致，耗时 `0.00` 秒；`--duplicates` 在不读取文件内容下输出 `未发现 >= 1 MiB 且同体积同扩展名的多文件组`。

## Tart `macos27` 原生全量门禁与深浅外观验收

Tart `macos27` 独立测试夹具全套 7 组原生无障碍回归门禁 **95 / 95 项全部通过**：

- `vm-function-gate.json`：13 / 13 通过（含候选缓存默认不勾选、权限遗漏显式展示、确认移入废纸篓、可恢复还原及源码/安装包保护）。
- `vm-navigation-gate.json`：8 / 8 通过（含快照增减历史、部分扫描不覆盖完整基线、文件夹选择器与取消扫描部分结果提示）。
- `021-analysis-gate.json`：14 / 14 通过（含物理/逻辑稀疏文件排行、自定义保护跨重启持久化与 10 列 CSV 报告导出校验）。
- `ui-style-gate.json`：10 / 10 通过（含确认 Sheet 风险免责声明、`Esc`/`⌘O` 键盘交互与导出面板状态释放）。
- `v050-ui-gate.json`：13 / 13 通过（含内存态面包屑下钻、对比方向筛选与工程工作区识别）。
- `v200-ui-gate.json`：14 / 14 通过（含旭日图/树状图/分栏树/占比条切换、APFS 本地快照只读 Sheet、疑似重复线索与三档扫描性能切换）。
- `v300-ui-gate.json`：23 / 23 通过（含智能护理健康环与五列纵向卡片、智能助手诊断 Sheet、安全保护启动项与安全防线、空间透镜左右双栏与 `bubble-lens-canvas`、系统清理双栏分类导航与 `cleanup-group-toggle` 开关往返、只读云盘空间透视子页 `cloud-storage-view` 且无清理触发按钮、我的杂物双时间轴与 `duplicate-compare-panel` 零清理触发、应用管理及卸载残留线索视图、性能优化实时矩阵与活跃应用卡片、`cpu-sparkline`/`memory-sparkline`、`performance-launch-link` 与点击 `performance-open-launch-items` 跳转至 `安全保护` 显示 `protection-tab-rail`，以及设置页 `low-space-threshold-picker` 分段选择器）。

全套 **31 张深浅色原生实机截图** 保存在 `outputs/screenshots/300-release/`（涵盖 `smartcare`、`bubble`、`overview`、`treemap`、`columns`、`suggestions`、`cloud`、`protection`、`confirmation`、`large`、`clutter-duplicates`、`applications`、`performance`、`types`、`projects`、`changes`、`updates` 的浅色与深色双外观），其中 `performance-dark.png`、`performance-light.png`、`updates-dark.png` 及既往阶段关键页面均经视觉核查无文字裁切、无重叠、深浅外观对比度清晰。

## 环境恢复与磁盘清理收尾

- VM `macos27` 内本次创建的测试路径（`~/AetherDisk-Release-QA-20261124`、`~/Applications/AetherDisk-Release-QA-20261124`、`/tmp/AetherDiskAX-20261124` 及对应测试快照）、测试进程与偏好设置均已恢复清理，`tart list` 确认 `macos27` 状态为 `stopped`。
- 宿主机已清理可再生成中间目录 `.build/`（`507 MiB` / `519,092 KiB`）、过程测试输出 `outputs/qa-300/`（`1.1 MiB` / `1,120 KiB`）与 `scripts/qa/__pycache__/`（`8.0 KiB` / `8 KiB`），清理产物合计 `520,220 KiB`（约 `508 MiB`），宿主机 `/` 剩余可用空间 `137 GiB`；`outputs/` 下无残留 `*.scan.json`（`0` 个），`codesign --verify --deep --strict outputs/AetherDisk.app` 通过，`aetherdisk-scan --version` 输出 `aetherdisk-scan 3.0.0`，仅保留唯一预览包 `outputs/AetherDisk.app`（`15 MiB`）、历版正式归档与正式验收截图（`38 MiB`）。

## 正式签名、Apple 公证与 Ed25519 验签（3.0.0 · 2026112501）

Developer ID Application: YanNan Chen (5984KQD4D7)。Sparkle 嵌套 XPC/Autoupdate/Updater 组件、Sparkle.framework、CLI `aetherdisk-scan` 与 `AetherDisk.app` 逐层启用 Hardened Runtime 并附带时间戳签名。

- App 公证 Accepted：`6d7cff8b-2260-4d00-9daf-8c6ff9622850`（`outputs/releases/3.0.0-2026112501/notarization-app.json`）。
- DMG 公证 Accepted：`698978b2-e6c7-4e6c-9825-4f65dd588172`（`outputs/releases/3.0.0-2026112501/notarization-dmg.json`）。
- App 与 DMG 公证票据均已 `stapler staple` 装订与 `stapler validate` 验证通过，`spctl --assess` 均为 `accepted / source=Notarized Developer ID`；只读挂载 `AetherDisk-3.0.0-arm64.dmg` 核对卷名 `AetherDisk 3.0.0`、`Applications` 软链、`安装说明.txt` 与 `Info.plist`（`3.0.0` / `2026112501` / `AetherDiskRelease = true` / `SUFeedURL = https://aethernative.com/apps/aetherdisk/appcast.xml` / `SUPublicEDKey = NtKT+Grl0IhrUwpJJb5a4Lulft66JG+GqgUhx25LD2E=`）后干净卸载。
- DMG SHA256：`4a1ad5b6b9fb564eb04c00555b73af9e3a0b87591069b62109bb3acbe5394cf9`（长度 `5,591,128` 字节）。
- 更新包 Ed25519 签名（`4p7s91hdNUnqmccB59eZ6Xin6JWAC4ZJmx4ly11ngorosMRhCx3jqqMWl1m3KmxcqppqeI30uGzgu8zxhdGzCA==`）与完整签名 Feed（`n+oE3F5ZwWqSfPBG4bzOCboJo4oXoC0vM1w3RwnIrUnuyjSZzRGruR5aO1iiNgCOtvdbgAVkvJKqmk+Rb2ypAg==`，长度 `1142`）通过公开 Ed25519 公钥 `NtKT+Grl0IhrUwpJJb5a4Lulft66JG+GqgUhx25LD2E=` 校验通过，且对 DMG 与 Feed 各篡改 1 字节均被拒绝。
- GitHub Release `v3.0.0`（https://github.com/bcblr1993/AetherDisk/releases/tag/v3.0.0）已发布正式 DMG、源码包（`AetherDisk-3.0.0-source.tar.gz`，`2,071,773` 字节，SHA256 `d67010b21ace71787b27868f0217f738499228cf6187a73ecb0ab1c66bc8ad50`）、`SHA256SUMS.txt`、`appcast.xml`、`notarization-app.json` 与 `notarization-dmg.json`。

## 真实 Sparkle 应用内升级验收（2.0.0 → 3.0.0）与发布后清理

2.0.0 (`2026112301`) → 3.0.0 (`2026112501`) 真实 Sparkle 应用内升级端到端验收（Tart `macos27` 干净独立基线，`scripts/qa/upgrade_gate.py`）全部通过：

- 线上官网 Feed `https://aethernative.com/apps/aetherdisk/appcast.xml` 实测 SHA-256 为 `f6a8f781655f2fd173a4c70b1367823200bbdb022ef1a6f3ecf11d15143bfeac`，与本地签名清单 `outputs/releases/3.0.0-2026112501/appcast.xml` 逐字节一致。
- 2.0.0 成功识别更新并完成下载、Ed25519 验签、替换安装与重启为 3.0.0（`2026112501`），升级后主二进制 SHA-256（`493b50aa6f4dd682a89adfd9b145dd848e8b134f07e60e267ac01cf746ff88a3`）与正式发行包完全匹配；再次检查更新提示「您使用的就是最新版」。
- 2.0.0 历史扫描快照（`8375121e14b7dde157e0eac4e8ea8fb59a43a82e4dd4df050cde9c648feb87cc`）、受保护源码与安装包、自动检查更新开关及自定义保护路径（`Developer/Safe/.build`）完整保留；3.0.0 正常加载旧版快照并在「占用变化」「文件类型」页面呈现历史对比与新版分析。
- 升级验收后 VM 内全部 QA 目录、测试偏好、扫描历史与 LaunchServices 注册均已彻底恢复清理，`macos27` 已停止。
- 发布收尾后宿主机已清理 `.build/`（`499 MiB` / `511,460 KiB`）、`outputs/releases/3.0.0-2026112501/AetherDisk.app` 解包副本（`15 MiB` / `15,692 KiB`）、过程升级日志 `outputs/logs/`（`108 KiB`）与 `scripts/qa/__pycache__/`（`12 KiB`），释放合计 `527,272 KiB`（约 `515 MiB`），宿主机 `/` 剩余可用空间 `136 GiB`（`143,076,604 KiB`）；无残留挂载或 `.scan.json`，保留唯一正式包 `outputs/AetherDisk.app`（`codesign` 与 `spctl` 均通过 `accepted / source=Notarized Developer ID`）、历版正式归档与正式验收截图。

历史版本验收记录分别保存在 [VERIFICATION-2.0.0.md](VERIFICATION-2.0.0.md)、[VERIFICATION-1.0.2.md](VERIFICATION-1.0.2.md)、[VERIFICATION-1.0.1.md](VERIFICATION-1.0.1.md)、[VERIFICATION-1.0.0.md](VERIFICATION-1.0.0.md)、[VERIFICATION-0.6.0.md](VERIFICATION-0.6.0.md)、[VERIFICATION-0.5.0.md](VERIFICATION-0.5.0.md)、[VERIFICATION-0.4.0.md](VERIFICATION-0.4.0.md) 与 [VERIFICATION-0.3.0.md](VERIFICATION-0.3.0.md)。
