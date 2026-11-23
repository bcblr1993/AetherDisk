# AetherDisk 1.0.2 正式发布验收

日期：2026-11-07（Asia/Shanghai）。版本 1.0.2，构建 2026110704，Apple Silicon、macOS 14+。

## 本版改动

- **全页面统一交互行组件（`DiskInteractiveRow`）**：为磁盘概览、清理建议、占用变化、跨目录大文件与工程洞察所有列表行统一提供整行圆角悬停高亮（`onHover`）、选中态高亮与整行点击热区（`.contentShape`）。
- **工程标识严格校验（`RuleCatalog.projectMarkers(in: [BulkEntry])`）**：修复扫描识别开发工程时未过滤符号链接或同名目录的问题，要求工程清单文件（如 `Package.swift`、`Cargo.toml`、`package.json`）必须为真实普通文件（`S_IFREG`），`.git` 必须为真实目录或普通文件且绝不为符号链接。
- **跨页面概览跳转与父级浏览边界收敛（`HierarchyBrowser.parentScope` & `resolveNavigationTarget`）**：支持从「占用变化」列表行、「持续增长热点」胶囊与「工程洞察」一键跳转到概览页对应目录层级；子目录内存浏览时自动隐藏顶层「扫描上一级」按钮，避免与「返回上一层浏览」产生误触冲突。
- **跨页勾选缓存筛选器重置与受保护项净化（`RecommendationQuery.sanitizedSelection`）**：从工程洞察点击「前往清理建议」时自动重置旧筛选条件并过滤已受保护或失效的缓存路径，确保已勾选缓存立即可见。
- 清理仍仅在用户显式确认并重新校验后移入系统废纸篓，禁止永久删除或自动清空。

## 核心与只读扫描

86 项核心测试全部通过，0 失败（采用 TDD 流程新增 3 项单元测试覆盖 `BulkEntry` 工程标识符号链接/非普通文件过滤、面包屑父目录边界与跨页导航解析、清理建议勾选集合安全净化）；Release 编译与打包脚本语法检查通过。

最终发行包内 CLI 真实只读扫描 `~/Downloads`：11 个文件、6 个目录、0 个未读取路径、360 KiB（逻辑大小 330 KiB），与 `du -xsk` 一致，耗时约 0.00 秒。不是可释放空间或全系统容量承诺。

## 签名、公证与安装

Developer ID Application: YanNan Chen (5984KQD4D7)。Sparkle 嵌套组件、框架、CLI 和 App 逐层签名，Hardened Runtime 与时间戳有效。

- App 公证 Accepted：`a7812091-1c6c-49ce-9097-b4d8d5a36fe5`。
- DMG 公证 Accepted：`aadc0b14-a233-4fa5-a8ff-66f7ecc66ee5`。
- App 和 DMG 票据已装订并验证，`spctl --assess` 均为 `accepted / source=Notarized Developer ID`。
- DMG SHA256：`132d17f8483a8a75cf381ff48a989653c8c4eadaaefa067307da1faa992580a9`（长度 `3,757,136` 字节）。
- 更新包 Ed25519 签名（`Xf1RxMoufL/67X0FTi+s6GNM9pC+otxtL1uCfb85Y0qk1ee+70z9mj241cXvOWb9mUqXUZfB9qJiPsc2K8eYBw==`）和完整签名 Feed（`Mcefg3R1tG1l3oOerL/ZS0LKL3LFYIfr193oweK42Y7QCmbyia11bLsLRFAjaTsoJ6megolsddajZnkPsSWUAg==`，长度 `1142`）用公开 Ed25519 公钥验证成功，同长度篡改包被拒绝。

## 原生回归与清理收尾

1.0.1、1.0.0、0.6.0、0.5.0、0.4.0 与 0.3.0 验收记录分别保存在 [VERIFICATION-1.0.1.md](VERIFICATION-1.0.1.md)、[VERIFICATION-1.0.0.md](VERIFICATION-1.0.0.md)、[VERIFICATION-0.6.0.md](VERIFICATION-0.6.0.md)、[VERIFICATION-0.5.0.md](VERIFICATION-0.5.0.md)、[VERIFICATION-0.4.0.md](VERIFICATION-0.4.0.md) 与 [VERIFICATION-0.3.0.md](VERIFICATION-0.3.0.md)。
