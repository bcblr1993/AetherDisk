# AetherDisk 2.0.0 正式发布验收

日期：2026-11-23（Asia/Shanghai）。版本 2.0.0，构建 2026112301，Apple Silicon、macOS 14+。

## 本版改动

- **四种交互式空间分布视图（`Visualization.swift` & `SunburstView` / `TreemapView` / `MillerColumnsView`）**：磁盘概览页新增「旭日图（多环扇区联动）」「树状图（Squarified Treemap）」「分栏树（Miller Columns）」「占比条」切换器（`overview-visual-mode`）与「按目录 / 按类型 / 按陈旧度 / 按保护」四种配色模式（`visual-color-mode`），受保护节点附带斜纹与徽章标识，支持点击选中、二次点击目录快速下钻及 `⌘↑` 返回上一级。
- **三档磁盘友好扫描策略与有界并发（`ScanPerformanceProfile` & `Scanner.swift`）**：支持「节能低 I/O」（单线程 + `IOPOL_THROTTLE`）、「均衡并发」（推荐，最多 4 路并发 + `IOPOL_THROTTLE`）与「极速并发」（最多 6 路并发）；仅当根目录直接子目录 $\ge 4$ 个时启用顶层有界并发，通过值类型 `InodeKey` 进行硬链接去重，常规节点留存预算升级至 `40,000`（缓存候选 `400`、深层大目录 `1,500`）。
- **挂载卷切换、APFS 本地快照与废纸篓只读透视（`VolumeSystem.swift`）**：侧边栏新增挂载卷切换（`volume-switcher`），外部卷严格锁定「仅只读分析」并隐藏所有清理入口；概览容量卡支持只读 `tmutil listlocalsnapshots` 快照透视（绝不删除或干预系统快照）、`~/.Trash` 只读大小提示与设置页「完整磁盘访问权限」只读检测。
- **纯元数据疑似重复大文件线索与原生体验增强**：新增 `DuplicateSizeGroup`（仅按 $\ge 1\text{ MiB}$ 唯一 inode 的逻辑大小与扩展名分组，绝不读取文件内容或计算哈希）、基于原生 `QLPreviewPanel` 的文件只读快速预览（`⌘Y`）、真实文件夹拖放扫描（`lstat` 严格拒绝符号链接与文件）、占用变化页多快照走势图（`SnapshotTrendChart`）及文件类型/工程缓存比例条。
- **规则与 CLI 2.0 扩充**：新增 PyTorch / Playwright / Puppeteer / pre-commit / Bazel / Electron / Cypress 工具缓存及 Zig（`.zig-cache`/`zig-out`）、Elixir（`_build`）、CMake（`cmake-build-debug`/`cmake-build-release`）、Rspack（`.rspack_cache`）构建规则（`regular` 清单校验）；`aetherdisk-scan` 新增 `--profile`、`--duplicates`、`--volumes`、`--version`，CSV 保持 10 列并新增 `duplicate_suspect` 分节。
- 清理仍仅在用户显式确认并重新校验后移入系统废纸篓，禁止永久删除或自动清空。

## 核心与只读扫描

`swift build --jobs 4 -Xswiftc -warnings-as-errors` 零警告通过；`swift test --jobs 4` 全部 103 项核心测试通过，0 失败（含新增 `Core2Tests` 17 项与 `SafetyAuditTests` 23 项，覆盖三档并发与 `du -xsk` 一致性、`DuplicateSizeGroup`、旭日图/树状图/分栏树几何与命中测试、`VolumeSystem` 只读探测与快照解析、扩充缓存规则、1.0.2 快照兼容解码、CLI 参数解析与静态安全审计）。

最终发行包内 CLI 真实只读扫描 `~/Downloads`（`aetherdisk-scan ~/Downloads --duplicates --volumes`）：70 个文件、13 个目录、0 个未读取路径、已分配 `2,068,048 KiB`（`2,117,681,152` 字节，逻辑大小 `2,067,874 KiB`），与 `du -xsk ~/Downloads`（`2068048`）精确一致，耗时 `0.00` 秒。不是可释放空间或全系统容量承诺。

## 签名、公证与安装

Developer ID Application: YanNan Chen (5984KQD4D7)。Sparkle 嵌套组件、框架、CLI 和 App 逐层签名，Hardened Runtime 与时间戳有效。

- App 公证 Accepted：`64653dee-73d8-4213-a62d-238c307989cf`。
- DMG 公证 Accepted：`9d53cdc7-c089-4bf2-80cf-f10584d90aa0`。
- App 和 DMG 票据已装订并验证，`spctl --assess` 均为 `accepted / source=Notarized Developer ID`；只读挂载 `AetherDisk-2.0.0-arm64.dmg` 核对卷名 `AetherDisk 2.0.0`、`Applications` 链接、`安装说明.txt` 与 `Info.plist`（`2.0.0` / `2026112301` / `AetherDiskRelease = true`）后干净卸载。
- DMG SHA256：`112ac435492092e0363da858ccd7135143af1a2386e57e0cabecfe34e815d7c9`（长度 `4,221,595` 字节）。
- 更新包 Ed25519 签名（`TWY0vS3vx9znbyt/+b1pkOAIl9t2sRpjzn5u5MzPDjnQ11YbuX8VNqK/de7FC0gvP9T3KTO6vJ8uOHI+VivsCg==`）和完整签名 Feed（`ndIm56f/zC3krz+x11LtfOvXz9p6aBjuXKOEvl6lbNfwlX0b5XKLQwo8AgK5CAjM1sPB66ILF1hv4C8q0wzkDg==`，长度 `1142`）用公开 Ed25519 公钥 `NtKT+Grl0IhrUwpJJb5a4Lulft66JG+GqgUhx25LD2E=` 验证成功，同长度篡改 DMG 与篡改 Feed 均被拒绝。

## 原生回归与清理收尾

Tart `macos27` 原生全量回归门禁（`outputs/qa-200/`）全部通过：`vm-function-gate.json`（13/13）、`vm-navigation-gate.json`（8/8）、`021-analysis-gate.json`（14/14）、`ui-style-gate.json`（10/10）、`v050-ui-gate.json`（13/13）与 `v200-ui-gate.json`（14/14）；全套 16 张深浅色截图保存在 `outputs/screenshots/200-release/`，VM 临时测试路径与偏好已清理恢复。

1.0.2 (`2026110704`) → 2.0.0 (`2026112301`) 真实 Sparkle 应用内升级端到端验收（Tart `macos27`，证据位于 `outputs/logs/200-upgrade-*`）全部通过：

- 线上官网 Feed `https://aethernative.com/apps/aetherdisk/appcast.xml` 实测 SHA-256 为 `4a3fe04263fbeec71d889fcfbd137d33934eb308aabd1221a47ec872bb42591a`，与本地签名清单逐字节一致。
- 1.0.2 成功识别更新并完成下载、Ed25519 验签、替换安装与重启为 2.0.0（`2026112301`），升级后主二进制 SHA-256 与正式发行包完全匹配；再次检查更新提示「您使用的就是最新版」。
- 1.0.2 历史扫描快照、受保护源码与安装包、自动检查更新开关及自定义保护路径（`Developer/Safe/.build`）完整保留；2.0.0 正常加载旧版快照并在「占用变化」「文件类型」页面呈现历史对比与新版分析。
- 升级验收后 VM 内全部 QA 目录、临时进程、测试缓存与偏好已彻底恢复并同步，`macos27` 已停止。

1.0.2、1.0.1、1.0.0、0.6.0、0.5.0、0.4.0 与 0.3.0 验收记录分别保存在 [VERIFICATION-1.0.2.md](VERIFICATION-1.0.2.md)、[VERIFICATION-1.0.1.md](VERIFICATION-1.0.1.md)、[VERIFICATION-1.0.0.md](VERIFICATION-1.0.0.md)、[VERIFICATION-0.6.0.md](VERIFICATION-0.6.0.md)、[VERIFICATION-0.5.0.md](VERIFICATION-0.5.0.md)、[VERIFICATION-0.4.0.md](VERIFICATION-0.4.0.md) 与 [VERIFICATION-0.3.0.md](VERIFICATION-0.3.0.md)。
