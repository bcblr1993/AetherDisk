# AetherDisk 1.0.0 正式发布验收

日期：2026-11-07（Asia/Shanghai）。版本 1.0.0，构建 2026110702，Apple Silicon、macOS 14+。

## 本版改动

- **交互式空间占比图（`SpaceMapLayout`）**：概览页新增比例空间分块条与交互胶囊，自动归并小于 2% 的长尾小项为「其余 N 项」，点击即可联动定位右侧详情检查器。
- **多快照趋势时间线与持续增长热点预警（`ScanTrendAnalyzer`）**：历史完整扫描快照上限提升至 10 份；占用变化页自动识别连续 $\ge 3$ 次快照单调增长的目录并高亮展示累计增长量与连涨次数。
- **APFS 卷弹性可回收空间透视（`VolumeSpace.purgeableNote`）**：结合 `volumeAvailableCapacityForOpportunisticUsageKey` 识别系统弹性可回收空间（含 APFS 本地快照与系统暂存），明确解释目录统计与立即可用空间差异。
- **本机清理审计账本（`CleanupAuditStore`）**：在 `~/Library/Application Support/AetherDisk/cleanup-audit.json` 持久化保留最近 50 条已确认移入废纸篓的操作收据，清理建议页底部展示最近移入废纸篓记录。
- **`aetherdisk-scan` CLI 1.0**：新增 `--csv <路径>`、`--compare <旧快照JSON>` 与 `--top <数量>` 参数，支持命令行直接导出 10 列安全转义 CSV 报告与快照差异对比。
- 清理仍仅在用户显式确认并重新校验后移入系统废纸篓，禁止永久删除或自动清空。

## 核心与只读扫描

79 项核心测试全部通过，0 失败（采用 TDD 流程新增 5 项单元测试覆盖空间图归一化与长尾归并、多快照时间线与持续增长热点检测、APFS 弹性可回收空间计算、本机清理审计账本原子持久化与容量上限、CLI 参数解析与对比格式化）；Release 编译与打包脚本语法检查通过。

最终发行包内 CLI 真实只读扫描 Downloads：11 个文件、6 个目录、0 个未读取路径、360 KiB（逻辑大小 330 KiB），与 `du -xsk` 一致，耗时约 0.00 秒。不是可释放空间或全系统容量承诺。

## 签名、公证与安装

Developer ID Application: YanNan Chen (5984KQD4D7)。Sparkle 嵌套组件、框架、CLI 和 App 逐层签名，Hardened Runtime 与时间戳有效。

- App 公证 Accepted：`a325e26d-80f4-4034-9a35-5c0a5dc44f98`。
- DMG 公证 Accepted：`1a0d4c63-27d0-417e-91e7-24f8e0befb60`。
- App 和 DMG 票据已装订并验证，`spctl --assess` 均为 `accepted / source=Notarized Developer ID`。
- 实际只读挂载核对卷名 `AetherDisk 1.0.0`、`Applications` 快捷方式、`安装说明.txt`，以及正式版标记和构建号 `2026110702`，核验后立即卸载临时挂载点。
- DMG SHA256：`8e1e95610c2778e5de37274bee4f26283af5cdaadb7ef24b1eb04fee6053378f`（长度 `3,699,790` 字节）。
- 更新包 Ed25519 签名（`h9Vc8fS1P5xQeMGJdkeYLORP4W9jdIh7JDoubUvgqHW+HMvcqoGnMH0ws0OpYzluv2HbqJPrFMgB0JbvwfypBw==`）和完整签名 Feed（`uRE01FMu48tsvYAfDmCDurcNgAw6cYFi1EjnKNTR05jGoTGnVTGaEq/Pm3yhcJos9a5ykB1g5UBqknmZTkyzBA==`，长度 `1142`）用公开 Ed25519 公钥验证成功，同长度篡改包被拒绝。

## 原生回归与清理收尾

Tart `macos27` 原生交互门禁（`function_gate.py`、`navigation_gate.py`、`analysis_gate.py`、`ui_style_gate.py`）全部兼容通过，测试结束后恢复 VM 环境并保持 `macos27` 停止状态。0.6.0、0.5.0、0.4.0 与 0.3.0 验收记录分别保存在 [VERIFICATION-0.6.0.md](VERIFICATION-0.6.0.md)、[VERIFICATION-0.5.0.md](VERIFICATION-0.5.0.md)、[VERIFICATION-0.4.0.md](VERIFICATION-0.4.0.md) 与 [VERIFICATION-0.3.0.md](VERIFICATION-0.3.0.md)。
