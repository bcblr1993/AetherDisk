## 3.0.0 · 2026-11-25

- **全面对齐 CleanMyMac 5 视觉体系与无障碍平滑动效（`Theme.swift` & `ContentView.swift`）**：重构为内嵌悬浮圆角毛玻璃侧边栏（顶部「智能助手」胶囊 + 严格对齐 CleanMyMac 5 的「智能护理、系统清理、安全保护、性能优化、应用管理、我的杂物、空间透镜」七大核心模块与三大实用工具）、立体高光渐变模块徽章（`ModuleIconBadge`）、十套专属色彩舞台光晕背景（`ModuleStagePalette` & `StageBackground`）、左右双栏欢迎英雄舞台（`ModuleHeroStage`）及无底栏遮挡的悬浮发光圆形主控球（`CircularActionOrbBar`）；新增 `DiskMotion` 统一动效控制，全面适配 `accessibilityReduceTransparency`（实色高对比面板与边框降级）与 `accessibilityReduceMotion`（静默旋转扫描环、呼吸光晕与即时页面切换）。
- **智能护理五列纵向卡片舞台与智能助手（`SmartCareView.swift` & `SystemHealth.swift`）**：新增旗舰主页「智能护理（Smart Care）」，一屏免滚动展示健康指数评分环与并排五列纵向毛玻璃卡片（系统清理、安全保护、性能优化、应用管理、空间透镜），配套「智能助手（Smart Assistant）」透明诊断抽屉与低空间阈值只读预警整合。
- **安全保护只读透明审计模块（`ProtectionAudit.swift` & `ProtectionView.swift`）**：新增 100% 纯元数据只读「安全保护（Protection）」模块，分栏审计 `LaunchAgents`/`LaunchDaemons` 后台启动代理元数据、SSH/GPG/Keychains/Git 硬保护防线与 `Downloads` 下载安装包（不读文件内容、不改系统配置）。
- **Space Lens 左右同屏双栏与交互式比例气泡透镜（`BubbleLens.swift`、`BubbleLensView.swift` & `OverviewView.swift`）**：空间透镜升级为「左目录透镜树 + 右比例气泡画布」左右同屏双栏布局；新增黄金角切线无重叠圆球排布算法按面积比例呈现目录与文件球体，支持悬停放大胶囊、受保护斜纹光圈、单击选中与二次点击/双击下钻，与旭日图、树状图、分栏树、占比条组成五维空间透视。
- **系统清理主从双栏审阅、按应用分组与只读云盘透视（`SuggestionsAndChangesViews.swift`、`CloudStorage.swift`、`CloudStorageView.swift` & `Rules.swift`）**：升级为「左分类导航 + 右明细审阅」双栏布局，支持 `RecommendationQuery.groupedByApplication` 按应用/工具链折叠透视；新增「云盘空间只读透视（`CloudStorageInspector`）」区分本地物理驻留与 `allocated == 0 && logical > 0` 云端占位（绝不触发下载或云端删除）；扩充「应用日志与诊断（`~/Library/Logs/*`）」「已保存窗口状态（`~/Library/Saved Application State/*.savedState`）」及 Homebrew/Zig/sccache/ccache/JetBrains/Deno/Prisma/Windsurf 等规则，自动排除应用自身运行状态并全程经 `SafetyInspector` 指纹与保护规则二次复核。
- **应用管理三栏透视与我的杂物双时间轴（`Applications.swift`、`ApplicationsView.swift`、`DirectoryHandle.swift`、`Scanner.swift`、`Analysis.swift` & `AnalysisViews.swift`）**：新增纯元数据只读「应用管理」模块，三栏透视 `/Applications` 与 `~/Applications` 应用体积、来源标识、关联缓存及疑似卸载残留线索（`.app` 本体严格只读保护）；`DirectoryHandle`/`Scanner` 只读采集 `ATTR_CMN_ACCTIME`（`accessedAt`）并向目录聚合最大值（向后兼容旧版 JSON），驱动「我的杂物」按修改时间/访问时间双时间轴筛选、`clutterSummary` 资产概览卡片与 `DuplicateSizeGroup.comparisonSummary` 疑似重复快速对比面板（严格零清理删除入口）。
- **性能优化趋势图、低空间只读阈值与 `MenuBarExtra`（`SystemHealth.swift`、`PerformanceAndAssistantViews.swift`、`AppModel.swift` & `AppUpdater.swift`）**：基于 Darwin Mach `host_statistics64`、`host_processor_info`、IOKit 电源与 `getifaddrs` 网口计数只读展示内存压力与分布、CPU 负载与散热、电源状态、实时网络吞吐与活跃应用；新增有界 30 采样 `TelemetryHistoryBuffer` 与 `TelemetrySparkline` 趋势折线图、`LowSpaceEvaluator` 用户可调低空间只读预警阈值（`10/20/50/100 GiB`）、`后台启动项详情联动` 一键直达「安全保护」、macOS 顶部菜单栏健康弹窗（`MenuBarExtra`）与 `aetherdisk-scan --apps --health --cloud` CLI 参数。

## 2.0.0 · 2026-11-23

- **多视图交互式空间可视化（`Visualization.swift` & `SunburstView` / `TreemapView` / `MillerColumnsView`）**：概览页新增「旭日图」「树状图」「分栏树」「占比条」四种交互式空间视图，支持「按目录」「按类型」「按陈旧度」「按保护」四种配色语义、受保护节点斜纹标识、点击选中与再次点击目录快速下钻（`⌘↑` 返回上一级）。
- **磁盘友好三档性能模式与有界并发扫描（`ScanPerformanceProfile` & `Scanner.swift`）**：新增「节能低 I/O」（单线程 + `IOPOL_THROTTLE`）、「均衡并发」（推荐，最多 4 路并发 + `IOPOL_THROTTLE`）与「极速并发」（最多 6 路并发）；仅当根目录直接子目录 $\ge 4$ 个时启用顶层有界并发与线程级磁盘 I/O 限流，采用值类型 `InodeKey` 硬链接去重，常规节点留存预算提升至 `40,000`（缓存池 `400`、深层大目录 `1,500`）。
- **挂载卷切换、APFS 本地快照透视与废纸篓只读观测（`VolumeSystem.swift`）**：侧边栏新增实时挂载卷切换（外部卷严格限定「仅只读分析」，完全隐藏清理建议与移入废纸篓入口）；概览容量卡新增只读「APFS 本地快照透视」（`tmutil listlocalsnapshots` 只读列举，绝不删除或干预系统快照）、`~/.Trash` 只读占用提示与设置页「完整磁盘访问权限」只读探测。
- **纯元数据疑似重复大文件线索（`DuplicateSizeGroup`）**：大文件页与 CLI 新增「疑似重复大文件线索」视图，仅依据 $\ge 1\text{ MiB}$ 唯一 inode 文件的 `(逻辑大小, 扩展名)` 归组统计潜在冗余空间，绝对不读取文件内容、不计算文件哈希，也不提供批量删除。
- **原生体验增强与可视化升级**：新增基于系统 `QLPreviewPanel` 的文件只读「快速预览」（`⌘Y` / 检查器 / 行操作）、窗口文件夹拖放分析（`lstat` 严格拒绝符号链接与单文件）、占用变化页「多快照占用走势图（`SnapshotTrendChart`）」、文件类型与工程洞察比例条。
- **规则与 CLI 2.0 扩充**：新增 PyTorch / Playwright / Puppeteer / pre-commit / Bazel / Electron / Cypress 工具缓存及 Zig（`.zig-cache`/`zig-out`）、Elixir（`_build`）、CMake（`cmake-build-debug`/`cmake-build-release`）、Rspack（`.rspack_cache`）构建规则（`regular` 清单校验）；`aetherdisk-scan` 新增 `--profile`、`--duplicates`、`--volumes`、`--version`，CSV 新增 `duplicate_suspect` 10 列分节。

## 1.0.2 · 2026-11-07

- **全页面统一交互行组件（`DiskInteractiveRow`）**：统一磁盘概览、清理建议、占用变化、大文件与工程洞察列表行的圆角悬停高亮与整行热区。
- **工程标识严格校验（`RuleCatalog.projectMarkers(in: [BulkEntry])`）**：要求语言工程清单必须为真实普通文件（`S_IFREG`），`.git` 必须为真实目录或普通文件且绝不为符号链接。
- **跨页面概览跳转与父级浏览边界收敛（`HierarchyBrowser.resolveNavigationTarget` & `parentScope`）**：支持从「占用变化」「持续增长热点」与「工程洞察」一键定位到概览对应目录，子目录浏览时自动收敛顶层父级按钮避免误触。
- **跨页勾选缓存净化（`RecommendationQuery.sanitizedSelection`）**：从工程洞察跳转清理建议时重置筛选器并过滤受保护/失效路径。

## 1.0.1 · 2026-11-07

- **全行点击热区与悬停反馈（`DiskSidebarButtonStyle`）**：补全侧边栏与列表行整行点击热区及悬停高亮，支持双击/二次点击目录直接下钻。
- **多快照尾部连续增长热点识别修复（`ScanTrendAnalyzer.growthHotspots`）**：从最新快照向前统计尾部连续增长轮次与累计增量；CLI 支持 `~/...` 波浪号展开与参数校验。

## 1.0.0 · 2026-11-07

- **里程碑正式版（1.0.0）**：在严格维持纯元数据只读扫描、不跟随符号链接、不跨卷、不读文件内容与显式二次确认后移入系统废纸篓的基础上，完成空间可视化、趋势预警、APFS 容量透视、本机清理审计账本与 CLI 1.0 体系化闭环。
- **交互式空间占比图（`SpaceMapLayout`）**：概览页新增比例空间分块条与交互胶囊，自动归并尾部长尾小项为「其余 N 项」，点击即可联动定位右侧详情检查器。
- **多快照趋势时间线与持续增长热点预警（`ScanTrendAnalyzer`）**：历史完整扫描快照上限提升至 10 份；占用变化页自动识别连续 $\ge 3$ 次快照单调增长的目录并高亮展示累计增长量与连涨次数。
- **APFS 卷弹性可回收空间透视（`VolumeSpace.purgeableNote`）**：结合 `volumeAvailableCapacityForOpportunisticUsageKey` 识别系统弹性可回收空间（含 APFS 本地快照与系统暂存），明确解释目录统计与立即可用空间差异。
- **本机清理审计账本（`CleanupAuditStore`）**：在 `~/Library/Application Support/AetherDisk/cleanup-audit.json` 持久化保留最近 50 条已确认移入废纸篓的操作收据，清理建议页底部展示最近移入废纸篓记录。
- **`aetherdisk-scan` CLI 1.0**：新增 `--csv <路径>`、`--compare <旧快照JSON>` 与 `--top <数量>` 参数，支持命令行直接导出 10 列安全转义 CSV 报告与快照差异对比。

## 0.6.0 · 2026-11-07

- 文件类型页新增「文件活跃度与陈旧分布」画像（近 30 天 / 30–90 天 / 90 天–1 年 / 1 年以上未改），单次只读扫描自动统计各时间桶占用与文件数，并支持一键联动筛选对应时间段的大文件。
- 清理建议页新增交互式缓存类别汇总胶囊、90 天未改陈旧筛选开关与「勾选 90 天未改可检项」快捷动作（严格保持默认不勾选、受保护项目绝不勾选、清理前复核确认并仅移入废纸篓边界）。
- 工程洞察页新增工程「源码与资产」净占用与构建缓存占比统计，支持按源码与资产排序及一键跳转「概览中查看」；CSV 扫描报告新增 `project` 工程分节导出。
- 扩充 Xcode 平台支持（`macOS/tvOS/visionOS DeviceSupport`）、全局工具链缓存（`~/Library/Caches/CocoaPods`、`~/.pub-cache`、`~/.sbt/boot`、`~/.ivy2/cache`、`~/.cache/huggingface/hub`、`~/.cache/playwright`）及工程构建缓存（`.angular/cache`、`.astro`、`.vite`、`.tox`、`.nox`、`.kotlin`，均要求真实工程清单佐证）识别规则，工程标志与源码保护同步覆盖 `go.mod`、`composer.json`、`Gemfile`、`mix.exs`、`angular.json`、`tox.ini`。

## 0.5.0 · 2026-11-05

- 引入 Darwin `getattrlistbulk(2)` 批量目录元数据只读扫描通道（带 `fstatat` 完整回退），大幅减少常规文件扫描系统调用开销，同时严格维持不跟随符号链接、不跨卷与 `du -xsk` 字节级一致性。
- 新增「工程洞察（Project Workspace Lens）」页面，自动识别含 Git 或语言工程清单的项目根目录，汇总项目总占用、可识别构建缓存占用与久未活跃状态，支持按总占用、构建缓存、久未活跃排序并一键联动清理建议。
- 文件类型页新增二级扩展名占用拆解，点击扩展名标签可直接跳转筛选对应大文件；详情栏新增 APFS 稀疏文件实际块占用比提示，清理建议页新增 90 天未改陈旧标识，主界面扫描按钮支持 `Command + R` 快捷键。
- 占用变化页支持按变化方向（全部 / 仅增长 / 仅减少）与关键词筛选，展示总变化摘要，并支持在多份历史扫描快照间切换对比基线。
- 扫描引擎向上聚合目录子树内最新文件修改时间，并保留最多 500 个 4 MiB 以上的深层目录（至第 6 层），使概览页支持更深层目录的内存态免重扫展开与“显示更多”分页加载。
- 扩充 Xcode（`iOS/watchOS DeviceSupport`）、包管理器（`~/.cargo/registry/cache`、`~/.pnpm-store`、`~/.bun/install/cache`、`~/.yarn/berry/cache`）与前后端项目构建缓存（`.next/cache`、`.nuxt`、`.turbo`、`.svelte-kit`、`.parcel-cache`、`.pytest_cache`、`.mypy_cache`，均需真实工程清单文件佐证）识别规则，CSV 扫描报告新增 `recommendation` 缓存建议分节。

## 0.3.0 · 2026-11-04

- 概览页支持按已分配大小、逻辑大小、文件数切换排序，并支持已缓存子目录的内存态快速展开与面包屑导航。
- 扩充 Xcode（CoreSimulator/Caches、DocumentationCache）、开发工具（go-build、pip、uv、Gradle、VS Code、Cursor）及项目构建目录（Maven target、CMake build、Python .ruff_cache）识别规则，并建立独立缓存候选池防止深层缓存被 20,000 节点预算遗漏。
- 清理建议页支持按状态（全部 / 可检查 / 已保护）、缓存类别及关键词筛选。
- 占用变化页支持顶层目录与深层子目录对比切换，并为每个目录保留最近 5 份完整扫描快照。
- 大文件页新增按修改时间（30 天 / 90 天 / 1 年未改）筛选陈旧大文件，详情栏显示最近修改日期。

## 0.2.2

- 统一按钮层级、尺寸、圆角、焦点和深浅色样式；危险清理使用红色操作。
- 清理确认和未读取路径面板共用标题、内容与操作栏，保留风险与保护提示。
- 统一搜索框和卡片，优化设置页宽度与对齐。
- 文件选择和 CSV 保存面板依附当前窗口，防止重复打开，取消后恢复操作状态。

## 0.2.1

- 清理确认页、设置页及官网增加风险和责任提示，提醒先备份、核对目录后再清理。

- 加固目录句柄遍历和变更检测，禁止跟随扫描中被替换的目录链接。
- 扩充源码、安装包和受保护容器规则；构建目录必须具备项目证据，Git 校验失败或未忽略文件拒绝清理。
- 清理前最后复核置于占用检查之后，统一目录内及跨候选硬链接统计与规范路径，完整报告保留项。
- 阻止清理检查期间切换扫描，部分扫描不覆盖完整历史，保留最后一次扫描进度列表。

# 更新记录

## 0.2.0 · 2026-10-24

- 新增跨目录大文件排行，支持大小、类型与路径筛选，区分逻辑大小和磁盘占用。
- 新增文件类型汇总，深层文件的统计不受目录展示上限影响。
- 新增自定义保护目录；包含它的缓存父目录也会被保护，执行前再次验证。
- 新增原生 CSV 报告导出与具体权限遗漏列表。
- 切换扫描目录时清除上一层搜索条件，设置窗口支持滚动。
- 大文件仅支持查看与 Finder 定位，不增加任意文件批量删除。
- 兼容 0.1.0 本地扫描历史；维持源码、安装包、凭据、聊天备份保护与确认后移入废纸篓的边界。

## 0.1.0 · 2026-10-24

首次正式发布：原生磁盘扫描、占用分析、历史比较、安全清理与 Sparkle 签名更新。
