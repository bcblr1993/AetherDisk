# AetherDisk 0.4.0 正式发布验收

日期：2026-11-04（Asia/Shanghai）。版本 0.4.0，构建 2026110402，Apple Silicon、macOS 14+。

## 本版改动

- 占用变化页支持按变化方向（全部 / 仅增长 / 仅减少）与关键词筛选，展示总已分配变化、增长/减少项数与文件数差值摘要，并支持在多份历史扫描快照间切换对比基线。
- 扫描引擎向上聚合目录子树内最新文件修改时间，并保留最多 500 个 4 MiB 以上的深层目录（至第 6 层），使概览页支持更深层目录的内存态免重扫展开与“显示更多”分页加载。
- 扩充 Xcode（`iOS DeviceSupport`、`watchOS DeviceSupport`）、包管理器（`~/.cargo/registry/cache`、`~/.pnpm-store`、`~/.bun/install/cache`、`~/.yarn/berry/cache`）与前后端项目构建缓存（`.next/cache`、`.nuxt`、`.turbo`、`.svelte-kit`、`.parcel-cache`、`.pytest_cache`、`.mypy_cache`，均需真实工程清单文件佐证）识别规则。
- CSV 扫描报告新增 `recommendation` 缓存建议分节，完整记录候选缓存路径、占用与保护状态。
- 清理仍仅在用户显式确认并重新校验后移入系统废纸篓，禁止永久删除或自动清空。

## 核心与只读扫描

66 项核心测试全部通过，0 失败（采用 TDD 流程新增 4 项单元回归测试覆盖方向对比与摘要、子树修改时间向上聚合与深层目录保留、现代前端与包管理器缓存规则、CSV 建议分节导出）；Release 编译与打包脚本语法检查通过。

最终发行包内 CLI 真实只读扫描 Downloads：73 个文件、36 个目录、0 个未读取路径、3,034,496 KiB（2.9 GiB），与 `du -xsk` 一致，耗时约 0.01 秒。不是可释放空间或全系统容量承诺。

## 签名、公证与安装

Developer ID Application: YanNan Chen (5984KQD4D7)。Sparkle 嵌套组件、框架、CLI 和 App 逐层签名，Hardened Runtime 与时间戳有效。

- App 公证 Accepted：`3b456cf3-5aa8-4109-b5b2-c03b677d8039`。
- DMG 公证 Accepted：`010f35e4-50ae-4fa2-9f1d-8c190ad9807e`。
- App 和 DMG 票据已装订并验证，`spctl --assess` 均为 `accepted / source=Notarized Developer ID`。
- 实际只读挂载核对卷名 `AetherDisk 0.4.0`、`Applications` 快捷方式、`安装说明.txt`，以及正式版标记和构建号 `2026110402`，核验后立即卸载临时挂载点。
- DMG SHA256：`bf00310254df73dbd06e0d6a3744c9e012a49070df3cfc095a03e1d35ee6ee26`（长度 `3,384,917` 字节）。
- 更新包 Ed25519 签名（`4DUpuWGpdeZC65CRTJUgHbfooii+uIj/bQOE8PmdeLv3fLHBSwIkXWODWcJaC878xs1RXPkJzkExZX8KIVxZAQ==`）和完整签名 Feed（`wpdVJRZsFCa1OXuGv/p24ZRh/uIKnfmx1EE+F/W+Me76yfvlnudnRLaxzgHoRa6kypH/TMM5MnjUFe/0ChM3Cw==`，长度 `1142`）用公开 Ed25519 公钥验证成功，同长度篡改包被拒绝。

## 原生回归与清理收尾

Tart `macos27` 执行 45 项既有原生交互断言（`function_gate.py` 13 项、`navigation_gate.py` 8 项、`analysis_gate.py` 14 项、`ui_style_gate.py` 10 项）及 v0.3.0 / v0.4.0 新增控件无障碍校验全部通过。测试结束后恢复 VM 偏好设置、清理本次测试创建的专用夹具与临时文件，并安全停止 `macos27` 虚拟机。0.3.0 验收记录保存在 [VERIFICATION-0.3.0.md](VERIFICATION-0.3.0.md)。
