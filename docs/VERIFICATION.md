# AetherDisk 0.5.0 正式发布验收

日期：2026-11-05（Asia/Shanghai）。版本 0.5.0，构建 2026110501，Apple Silicon、macOS 14+。

## 本版改动

- **底层 `getattrlistbulk(2)` 高速只读扫描内核**：采用 Darwin 内核 `getattrlistbulk`（`FSOPT_NOFOLLOW`、`64 KiB` 缓冲）批量读取目录内常规文件 `dev/ino/nlink/size/blocks/mtime/mode` 属性，对子目录与符号链接保持安全降级与边界校验，严格遵循硬链接去重、不跨卷、不跟随符号链接与不读取文件内容红线。
- **工程工作区洞察页（ProjectsPage）**：扫描过程识别至第 4 层含真实工程标志文件（`Package.swift`、`Cargo.toml`、`package.json`、`pom.xml`、`build.gradle`、`pyproject.toml`、`.xcodeproj` 等）的开发工程根目录，聚合工程总已分配占用与匹配的构建/依赖缓存占用，支持按总占用、可清理缓存或久未修改排序与关键词检索。
- **文件构成扩展名透视与 APFS 稀疏度提示**：在八大文件分类下聚合 Top 10 扩展名占比并支持一键填入大文件过滤词；详情检查器在逻辑大小显著大于已分配空间时展示 APFS 稀疏/内联存储说明，明确区分占用与可释放空间。
- **缓存建议分类汇总与陈旧标记**：清理建议页顶部新增分类可复核空间汇总条，对超过 90 天未修改的缓存项标注“90 天未改”，并支持 `Command + R` 快捷键重新扫描。
- **包含 0.4.0 全部增强**：占用变化页方向筛选（全部/仅增长/仅减少）、关键词搜索与多历史基线切换；目录子树修改时间向上聚合与深层目录免重扫展开；Xcode 设备支持、Cargo/pnpm/Bun/Yarn 缓存与现代前后端框架构建缓存规则；CSV 报告 `recommendation` 建议分节导出。
- 清理仍仅在用户显式确认并重新校验后移入系统废纸篓，禁止永久删除或自动清空。

## 核心与只读扫描

70 项核心测试全部通过，0 失败（采用 TDD 流程累计新增 8 项单元与安全审计测试覆盖 `getattrlistbulk` 与 `fstatat` 一致性及硬链接/符号链接边界、工程工作区识别与缓存聚合、扩展名细分与稀疏文件提示、建议分类汇总与陈旧判断、变化方向筛选与摘要、子树修改时间聚合与深层目录保留、现代前端与包管理器缓存规则、CSV 建议分节导出）；Release 编译与打包脚本语法检查通过。

最终发行包内 CLI 真实只读扫描 Downloads：74 个文件、36 个目录、0 个未读取路径、3,034,584 KiB（2.9 GiB），与 `du -xsk` 一致，耗时约 0.01 秒。不是可释放空间或全系统容量承诺。

## 签名、公证与安装

Developer ID Application: YanNan Chen (5984KQD4D7)。Sparkle 嵌套组件、框架、CLI 和 App 逐层签名，Hardened Runtime 与时间戳有效。

- App 公证 Accepted：`b52ec2e6-f6e4-4e93-90bc-6e0a226a16a0`。
- DMG 公证 Accepted：`2ed76771-0303-4abb-af46-675a0bc2c223`。
- App 和 DMG 票据已装订并验证，`spctl --assess` 均为 `accepted / source=Notarized Developer ID`。
- 实际只读挂载核对卷名 `AetherDisk 0.5.0`、`Applications` 快捷方式、`安装说明.txt`，以及正式版标记和构建号 `2026110501`，核验后立即卸载临时挂载点。
- DMG SHA256：`215a5812565f4f7497e492772831088eeb1f449d2350cc7b590a7abf70884d3f`（长度 `3,524,718` 字节）。
- 更新包 Ed25519 签名（`5aQcAzIQ1Clzji7QyrTAjz4drLc1ucHwZyJD1IXXkbou26BcU/nkl/xKhTHEGOXkX5yf5lKFexbv1vrhIRkiCw==`）和完整签名 Feed（`R73o3Y0kILq3aVOqIK7EZVQ1tr1mgoGJhPi0aW2jJzqieEry5sjA7xnF6zZ+Jekfj1vhWCBclgP2Qubot+lnAw==`，长度 `1142`）用公开 Ed25519 公钥验证成功，同长度篡改包被拒绝。

## 原生回归与清理收尾

Tart `macos27` 原生交互门禁（`function_gate.py`、`navigation_gate.py`、`analysis_gate.py`、`ui_style_gate.py`）全部兼容通过，测试结束后恢复 VM 环境并保持 `macos27` 停止状态。0.4.0 与 0.3.0 验收记录分别保存在 [VERIFICATION-0.4.0.md](VERIFICATION-0.4.0.md) 与 [VERIFICATION-0.3.0.md](VERIFICATION-0.3.0.md)。
