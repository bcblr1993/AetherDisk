# AetherDisk 0.6.0 正式发布验收

日期：2026-11-07（Asia/Shanghai）。版本 0.6.0，构建 2026110701，Apple Silicon、macOS 14+。

## 本版改动

- **文件活跃度与陈旧分布画像（`AgeBucket` / `AgeBucketUsage`）**：单次只读扫描自动按最后修改时间聚合全目录文件活跃度分布（近 30 天 / 30–90 天 / 90 天–1 年 / 1 年以上未改），在文件类型页新增活跃度分布卡片，支持一键联动跳转至大文件陈旧度筛选。
- **清理建议分类汇总胶囊与陈旧可检项筛选（`RecommendationQuery`）**：清理建议页新增交互式缓存类别汇总胶囊、「仅看 90 天未改」开关及「勾选 90 天未改可检项」快捷动作（严格保持默认不勾选、受保护项目绝不勾选、清理前复核确认并仅移入废纸篓边界）。
- **工程洞察「源码与资产」净占用与 CSV `project` 分节（`ProjectSummary`）**：新增工程 `nonCacheAllocated` 净占用与构建缓存占比统计，支持按源码与资产排序及一键跳转「概览中查看」；CSV 扫描报告新增 `project` 工程分节导出。
- **Xcode 全平台设备支持与多生态构建缓存规则扩充（`RuleCatalog`）**：扩充 `macOS/tvOS/visionOS DeviceSupport`、`~/Library/Caches/CocoaPods`、`~/.pub-cache`、`~/.sbt/boot`、`~/.ivy2/cache`、`~/.cache/huggingface/hub`、`~/.cache/playwright`，以及需真实工程清单佐证的 `.angular/cache`、`.astro`、`.vite`、`.tox`、`.nox`、`.kotlin` 构建缓存规则，并同步保护 `go.mod`、`composer.json`、`Gemfile`、`mix.exs`、`angular.json`、`tox.ini`。
- 清理仍仅在用户显式确认并重新校验后移入系统废纸篓，禁止永久删除或自动清空。

## 核心与只读扫描

74 项核心测试全部通过，0 失败（采用 TDD 流程新增 4 项单元与安全审计测试覆盖文件活跃度时间桶分布与旧快照兼容、建议陈旧筛选与未受保护可检项选择、工程非缓存净占用排序与 CSV 工程分节导出、Xcode 全平台设备支持与多生态缓存规则）；Release 编译与打包脚本语法检查通过。

最终发行包内 CLI 真实只读扫描 Downloads：11 个文件、6 个目录、0 个未读取路径、360 KiB（逻辑大小 330 KiB），与 `du -xsk` 一致，耗时约 0.00 秒。不是可释放空间或全系统容量承诺。

## 签名、公证与安装

Developer ID Application: YanNan Chen (5984KQD4D7)。Sparkle 嵌套组件、框架、CLI 和 App 逐层签名，Hardened Runtime 与时间戳有效。

- App 公证 Accepted：`7756e8da-721a-44b9-895e-0dcc85412faa`。
- DMG 公证 Accepted：`2e0317b0-83ce-480e-bd61-c1ef77749f06`。
- App 和 DMG 票据已装订并验证，`spctl --assess` 均为 `accepted / source=Notarized Developer ID`。
- 实际只读挂载核对卷名 `AetherDisk 0.6.0`、`Applications` 快捷方式、`安装说明.txt`，以及正式版标记和构建号 `2026110701`，核验后立即卸载临时挂载点。
- DMG SHA256：`5a695742421a0c2c978aa557ac6bef8565015132025db04486df2e8579792f68`（长度 `3,580,046` 字节）。
- 更新包 Ed25519 签名（`NScJPNB9qbrPyhuLir/j0gUnp8S/PZcRT6CMoyp1xsjr9VtnJIiC9Km/Dq9ePBcjbSlCYPBiwJ38tQ4xTFrjBA==`）和完整签名 Feed（`4Wit2icycKRyLCnyeF7/DJPlogg6zli+tHkmUTN36BlptFAa9GaZ8N4AU5HuiQRJeY2dhsnbYD9DMS9gMmT3CA==`，长度 `1142`）用公开 Ed25519 公钥验证成功，同长度篡改包被拒绝。

## 原生回归与清理收尾

Tart `macos27` 原生交互门禁（`function_gate.py`、`navigation_gate.py`、`analysis_gate.py`、`ui_style_gate.py`）全部兼容通过，测试结束后恢复 VM 环境并保持 `macos27` 停止状态。0.5.0、0.4.0 与 0.3.0 验收记录分别保存在 [VERIFICATION-0.5.0.md](VERIFICATION-0.5.0.md)、[VERIFICATION-0.4.0.md](VERIFICATION-0.4.0.md) 与 [VERIFICATION-0.3.0.md](VERIFICATION-0.3.0.md)。
