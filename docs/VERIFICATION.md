# AetherDisk 1.0.1 正式发布验收

日期：2026-11-07（Asia/Shanghai）。版本 1.0.1，构建 2026110703，Apple Silicon、macOS 14+。

## 本版改动

- **侧边栏与全页面整行热区及悬停响应修复（`DiskSidebarButtonStyle`）**：补全侧边栏「工作空间」与「快速扫描」全部菜单项的 `.contentShape(RoundedRectangle(cornerRadius: 9))` 整行点击热区与 `onHover` 悬停高亮反馈；移除列表行内会拦截鼠标点击的 `.textSelection(.enabled)`，改为右键菜单「复制路径」与悬停完整路径提示（`.help`），消除“点空白不响应”现象。
- **目录二次点击下钻与空间图联动（`HierarchyBrowser.nextBrowseAction`）**：首次点击目录行或空间占比图色块选中项目，再次点击已选中的可展开目录直接进入该目录层级；右侧详情检查器新增「展开此目录」快捷入口。
- **空间图保护状态完整透传（`SpaceMapBlock.isProtected`）**：`AppModel.rows` 统一合并用户自定义保护规则（`UserProtection.apply`），并在空间占比图胶囊上展示保护盾牌标识。
- **多快照尾部连续增长热点识别修复（`ScanTrendAnalyzer.growthHotspots`）**：修复历史快照早期曾缩减但最近连续增长时被漏检的问题，改为从最新快照向前统计尾部连续增长轮次与累计增量。
- **`aetherdisk-scan` CLI 参数校验与波浪号展开（`ScanCLIOptions.parse`）**：支持 `~/...` 路径展开并严格拦截缺失参数或未知选项。
- 清理仍仅在用户显式确认并重新校验后移入系统废纸篓，禁止永久删除或自动清空。

## 核心与只读扫描

83 项核心测试全部通过，0 失败（采用 TDD 流程新增 4 项单元测试覆盖目录二次点击下钻状态机、空间图自定义保护透传、历史快照尾部连续增长热点识别、CLI 路径展开与异常参数拦截）；Release 编译与打包脚本语法检查通过。

最终发行包内 CLI 真实只读扫描 `~/Downloads`：11 个文件、6 个目录、0 个未读取路径、360 KiB（逻辑大小 330 KiB），与 `du -xsk` 一致，耗时约 0.00 秒。不是可释放空间或全系统容量承诺。

## 签名、公证与安装

Developer ID Application: YanNan Chen (5984KQD4D7)。Sparkle 嵌套组件、框架、CLI 和 App 逐层签名，Hardened Runtime 与时间戳有效。

- App 公证 Accepted：`866e176e-d507-493e-86e7-b841273cbbd1`。
- DMG 公证 Accepted：`a9fd6f38-4e6e-41ea-beac-3c5ea7151b96`。
- App 和 DMG 票据已装订并验证，`spctl --assess` 均为 `accepted / source=Notarized Developer ID`。
- DMG SHA256：`72a5a2f3ddc731f4af6fc5cd388cc1e00b66273eced7731aa7335ea031ce8a09`（长度 `3,740,696` 字节）。
- 更新包 Ed25519 签名（`wEcRYAu7H/nhk7YZ+uTvHLzhCZo5l8zPnnbJd9sAY/UGVyy4Sc7p8s8hTHjBv0NCbGqL2fffZgEOc5HwK3l3Cw==`）和完整签名 Feed（`neNhSgdn92lP9hdBzyTy00DyAeMjzlnGLkrj8nEbtuvLwD0pFaBtYVYdJiHCwtWCXLfYv/sXmEkQfqVIqLBXBg==`，长度 `1142`）用公开 Ed25519 公钥验证成功，同长度篡改包被拒绝。

## 原生回归与清理收尾

1.0.0、0.6.0、0.5.0、0.4.0 与 0.3.0 验收记录分别保存在 [VERIFICATION-1.0.0.md](VERIFICATION-1.0.0.md)、[VERIFICATION-0.6.0.md](VERIFICATION-0.6.0.md)、[VERIFICATION-0.5.0.md](VERIFICATION-0.5.0.md)、[VERIFICATION-0.4.0.md](VERIFICATION-0.4.0.md) 与 [VERIFICATION-0.3.0.md](VERIFICATION-0.3.0.md)。
