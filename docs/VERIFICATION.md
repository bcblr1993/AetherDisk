# AetherDisk 0.3.0 正式发布验收

日期：2026-11-04（Asia/Shanghai）。版本 0.3.0，构建 2026110401，Apple Silicon、macOS 14+。

## 本版改动

- 概览页支持按已分配大小、逻辑大小、文件数排序切换，并支持已缓存子目录的内存态快速展开浏览与面包屑导航。
- 扩充 Xcode（CoreSimulator/Caches、DocumentationCache）、开发工具（go-build、pip/http-v2、uv、Gradle caches、VS Code、Cursor）及项目构建目录（Maven target 需真实 `pom.xml`、CMake build 需真实 `CMakeLists.txt`、Python `.ruff_cache` 需真实 `pyproject.toml`）识别规则，建立独立缓存候选池防止深层缓存被 20,000 节点展示预算饿死。
- 清理建议页新增按状态（全部 / 可检查 / 已保护）、缓存类别及关键词筛选。
- 占用变化页支持顶层目录与深层子目录对比切换（自动剔除已整体删除父目录的冗余子项），并为每个扫描目录保留最近 5 份完整扫描快照。
- 大文件页新增按修改时间（30 天 / 90 天 / 1 年未改）筛选陈旧大文件，详情栏展示最近修改日期。
- 清理仍仅在用户显式确认并重新校验后移入系统废纸篓，禁止永久删除或自动清空。

## 核心与只读扫描

62 项核心测试全部通过，0 失败（原有 57 项 + 新增 5 项单元回归测试）；Release 编译与打包脚本语法检查通过。

最终发行包内 CLI 真实只读扫描 Downloads：73 个文件、36 个目录、0 个未读取路径、3,034,496 KiB（2.9 GiB），与 `du -xsk` 一致，耗时约 0.01 秒。不是可释放空间或全系统容量承诺。

## 签名、公证与安装

Developer ID Application: YanNan Chen (5984KQD4D7)。Sparkle 嵌套组件、框架、CLI 和 App 逐层签名，Hardened Runtime 与时间戳有效。

- App 公证 Accepted：`70081f81-8543-4970-8aa4-a14e89947a50`。
- DMG 公证 Accepted：`705f879b-e295-4d4d-b195-8b654829a225`。
- App 和 DMG 票据已装订并验证，`spctl --assess` 均为 `accepted / source=Notarized Developer ID`。
- 实际只读挂载核对卷名 `AetherDisk 0.3.0`、`Applications` 快捷方式、`安装说明.txt`，以及正式版标记和构建号 `2026110401`，核验后立即卸载临时挂载点。
- DMG SHA256：`ff6ff6898d0c23a02d18de4cdb090936933bb0620bfd23992af5354fd333ffcb`（长度 `3,351,540` 字节）。
- 更新包 Ed25519 签名（`V612JLbaeYrhYNUbJMT/gt5+QOFIy3Gf3TZCk8z3QW5B4qx8Xf2wrR30DucHeXFlK4REvK18IrRFqSdhooI6BQ==`）和完整签名 Feed（`Mqs84pfnqImA56i3rbuDU34geN9CfDEEvw52JgzuVYsaSuZEszaPJvO1V1X+3ligRqVCH2njlKNDNr6+GnqTAw==`，长度 `1142`）用公开 Ed25519 公钥验证成功，同长度篡改包与被篡改 Feed 均被拒绝。

## 原生回归与清理收尾

Tart `macos27` 执行 45 项既有原生交互断言（`function_gate.py` 13 项、`navigation_gate.py` 8 项、`analysis_gate.py` 14 项、`ui_style_gate.py` 10 项）及 v0.3.0 新增控件无障碍校验全部通过。测试结束后已恢复 VM 偏好设置、清理本次测试创建的专用夹具与临时文件，并安全停止 `macos27` 虚拟机。0.2.2 验收记录保存在 [VERIFICATION-0.2.2.md](VERIFICATION-0.2.2.md)。
