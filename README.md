# AetherDisk

全面对齐 CleanMyMac 现代视觉与模块化体验的轻量原生 macOS 空间护理与系统透视工具。Swift 6 + SwiftUI / AppKit，Apple Silicon，macOS 14+。

当前正式发行版本为 **3.1.0**（构建 `2026112502`），唯一第三方生产依赖为 `Sparkle 2.10.0`。

官网：https://aethernative.com/apps/aetherdisk/
下载：https://github.com/bcblr1993/AetherDisk/releases/latest
更新源：https://aethernative.com/apps/aetherdisk/appcast.xml

## 核心模块与功能（对齐 CleanMyMac 5 七大核心模块 + 实用工具）

- **智能护理（Smart Care，`⌘1`）**：一屏免滚动全维只读体检主页，呈现健康指数圆环与 CleanMyMac 5 标志性并排五列纵向毛玻璃卡片（「系统清理、安全保护、性能优化、应用管理、空间透镜」，支持卡片内点击进入工作台或点击「展开摘要」就地展开 5 大维度只读快速审阅抽屉），搭配左上角「智能助手」胶囊与透明诊断建议列表。
- **系统清理（Cleanup，`⌘2`）**：CleanMyMac 风格「左分类 + 右明细」双栏审阅台，支持**按应用/工具链分组**折叠透视与**只读云盘空间透视**（`iCloud Drive` / `Google Drive` / `OneDrive` / `Dropbox` 本地驻留块 vs 云端占位体积对比，绝不触发下载或云端删除），覆盖网页与应用缓存、应用日志与诊断（`~/Library/Logs/*`）、已保存窗口状态（`~/Library/Saved Application State/*.savedState`）、Xcode 设备支持与编译缓存、Homebrew/Zig/sccache/ccache/JetBrains/Deno/Prisma/Windsurf 等开发缓存及项目构建目录；默认不勾选，二次确认后仅移入废纸篓。
- **安全保护（Protection，`⌘3`）**：100% 纯元数据只读安全与启动项透明审计模块，分栏巡检「后台启动代理（`LaunchAgents` / `LaunchDaemons` 元数据）」「隐私与保护防线（SSH/GPG/Keychains/Git 源码硬保护盾牌）」与「下载安装包核查（`Downloads` 内 `.dmg/.pkg/.app/.zip` 只读清点）」，不读文件内容、不篡改系统守护配置。
- **性能优化（Performance & MenuBarExtra，`⌘4`）**：基于 Darwin Mach、IOKit 与 BSD 网口接口只读监控内存压力与分布、CPU 负载与散热状态（内置有界 30 次采样 `TelemetrySparkline` 实时趋势折线图与均值/峰值读数）、电源健康、实时网络吞吐、活跃应用、挂载卷、APFS 本地快照、用户可调低空间只读阈值提醒（`10 / 20 / 50 / 100 GiB`）及「后台启动项详情联动」直达安全保护（绝不伪造内存清理、绝不强杀用户进程、绝不删除系统快照、绝不自动清理），并提供内置实时 CPU/内存双迷你波形与 3 秒轻量只读刷新的 macOS 顶部菜单栏健康弹窗。
- **应用管理（Applications，`⌘5`）**：纯元数据只读扫描 `/Applications` 与 `~/Applications`，三栏透视应用本体大小、来源标识（App Store / 独立安装）、基于系统元数据估算的未活跃天数与「久未使用」筛选排序、关联缓存/日志足迹与疑似卸载残留线索；所有 `.app` 本体严格受保护，绝不删除或卸载应用包。
- **我的杂物（My Clutter，`⌘6`）**：统一筛查「大文件与旧文件」「纯元数据疑似重复大文件线索」与「安装包与归档」，支持基于只读 `ATTR_CMN_ACCTIME` 采集的**双时间轴（按修改时间 / 按访问时间）**筛选、顶部资产概览卡片（媒体资产 / 安装包与归档 / 陈旧大文件）与疑似重复快速对比面板，区分实际磁盘块占用与稀疏文件逻辑体积，支持 `⌘Y` 原生 Quick Look 预览。
- **空间透镜（Space Lens，`⌘7`）**：采用 CleanMyMac 标志性「左目录透镜树 + 右比例气泡画布」左右同屏双栏布局，提供 **交互式比例气泡图（Bubble Lens）**（支持捏合手势与悬浮缩放条 `85%–180%` 平滑缩放/一键重置 `100%`、悬停径向射线高亮及两行元数据浮窗）及「旭日图」「树状图」「分栏树」「占比条」五种空间拓扑视图，支持四种配色模式、受保护斜纹标识、二次点击下钻与 `⌘↑` 返回上级。
- **实用工具（工程洞察、文件类型与占用变化）**：自动识别 Git 与主流语言工程及构建缓存占比；穿透统计全量文件扩展名与活跃度时间桶；保留最近 10 份完整扫描快照追踪增长热点。
- **磁盘友好并发、拖放扫描与无障碍自适应**：支持「节能低 I/O」「均衡并发（推荐）」「极速并发」（`IOPOL_THROTTLE` 线程级磁盘限流），支持真实文件夹拖入窗口发起只读扫描与 10 列安全转义 CSV 报告导出，并全面适配 macOS「减少透明度（`accessibilityReduceTransparency`）」高对比实色降级与「减弱动态效果（`accessibilityReduceMotion`）」动效静默。

## 运行

```sh
swift test --jobs 4
scripts/build-preview.sh
open outputs/AetherDisk.app
```

命令行扫描不启动 GUI，永远只读：

```sh
swift run aetherdisk-scan ~/Downloads --profile balanced --duplicates --volumes --apps --cloud --health
swift run aetherdisk-scan ~/Downloads --json /tmp/aetherdisk-downloads.json --csv /tmp/aetherdisk-downloads.csv
```

默认不会自动扫描，用户选择位置、拖入真实文件夹或点击底部圆形扫描主按钮后才开始。访问受隐私保护的目录时，权限不足会明确标记未读取路径，不会当作零占用或完整扫描。

## 清理边界

1. 仅限个人文件夹内、规则识别的真实缓存、历史日志与已保存窗口状态目录；外部卷严格只分析，无清理入口。
2. 源码扩展名、项目清单、Git 元数据/跟踪文件/未被忽略文件、应用包（`.app`）、安装包、xcarchive、文档报告、签名材料、聊天备份等会阻止整个候选目录清理。
3. 不跟随符号链接，不跨卷，不读取任何普通文件内容。发现权限遗漏则该候选不可清理。
4. 预览和执行均检查进程占用（`lsof`）；执行前重新核对 inode、大小、修改时间、变更时间、硬链接数等目录指纹。计划两分钟后失效且只能使用一次。
5. 构建目录要求真实普通文件清单佐证；受保护容器内部缓存不清理。Git 校验失败保留文件。
6. 批次先全部校验，再逐项移入系统废纸篓；操作错误立即停止，并报告已完成与失败项。
7. 不会自动清空废纸篓。移入废纸篓通常不会立即释放磁盘空间；实际容量变化另行显示。

## 统计与性能

扫描仅读取文件系统目录与元数据（`open`/`openat` + `getattrlistbulk`/`fstatat`/`fstat`/`lstat`/`statfs`），绝不读取文件内容。按值类型 `(dev, ino)` 对硬链接去重，分别统计已分配块数与逻辑长度。目录树保留预算有界（常规节点 `40,000`、缓存候选 `400`、深层大目录 `1,500`、大文件前 `200` 项），避免百万级文件引发无界内存增长。

历史记录只保存在 `~/Library/Application Support/AetherDisk/Scans`，清理审计账本只保存在 `~/Library/Application Support/AetherDisk/cleanup-audit.json`，均不上传。

## 应用内更新与验证

- 应用内更新说明参见 [docs/UPDATES.md](docs/UPDATES.md)。
- CleanMyMac 对齐架构与设计规范参见 [docs/CLEANMYMAC_ALIGNMENT_SPEC.md](docs/CLEANMYMAC_ALIGNMENT_SPEC.md)。
- 原生验收记录参见 [docs/VERIFICATION.md](docs/VERIFICATION.md)。

## 使用风险与责任

软件及清理建议可能存在问题或误判，请谨慎操作。重要文件请先备份，并逐项核对清理目录。误删或数据丢失由用户自行承担，开发者概不负责。
