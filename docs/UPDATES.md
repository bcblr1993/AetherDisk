# 应用内更新

使用 Sparkle 2.10.0，固定版本和 Git revision 见 Package.resolved。SDK 负责下载、EdDSA 签名验证、更新提示与安装，不使用自制替换脚本。

## 已实现

- 应用菜单「检查更新…」、侧栏设置页、系统设置窗口。
- 每日自动检查开关，禁用自动下载，不发送系统概况。
- 配置检查：HTTPS 地址、无 URL 内嵌凭据、真实 32 字节 Ed25519 公钥。
- `SURequireSignedFeed = true`、`SUVerifyUpdateBeforeExtraction = true`；同时要求 Feed 和更新包签名，解压前验证更新包。
- 没有正式配置时：显示开发预览状态、禁用自动检查，手动检查解释通道尚未开放。

## 正式上线前必须完成

1. 明确官网 AetherDisk 产品页、下载与 Feed 托管路径。拟沿用 `/apps/aetherdisk/appcast.xml`，当前未部署该路径。
2. 用 Sparkle 官方工具为 AetherDisk 建立独立发布签名身份，私钥仅在发布者钥匙串保存。不得复用其他产品私钥，不得写入仓库。
3. 构建配置注入 `AETHERDISK_UPDATE_FEED` 与 `AETHERDISK_UPDATE_PUBLIC_KEY`。公钥从发布签名身份导出，不能使用演示值。
4. 用 Developer ID 按内层工具、XPC、Updater、Sparkle framework、主应用顺序签名并开启 Hardened Runtime。当前 build-preview.sh 仅为 ad-hoc 开发签名，不是正式发布脚本。
5. 完成 Apple 公证、staple、Gatekeeper 与干净 VM 验收。
6. 在包含正式 `AetherDisk.app` 的新发布目录中执行 `scripts/generate-appcast.sh`。脚本要求公证 DMG、HTTPS 下载前缀和已配置签名的 App，读取钥匙串账户 AetherDisk；不会自动生成或导出私钥。
7. 发布签名 Feed 与最终 DMG。不得在签名之后编辑 Feed。
8. 使用上一构建号实际运行升级，验证新版本、签名与用户数据保留；并测试无更新、离线、错误签名与损坏包拒绝路径。

当前状态：SDK 与入口已接入；正式更新源、发布密钥和真实跨版本更新验收未完成，因此预览包不启用更新网络通道。

参考：
- https://sparkle-project.org/documentation/programmatic-setup/
- https://sparkle-project.org/documentation/publishing/
- https://sparkle-project.org/documentation/customization/
