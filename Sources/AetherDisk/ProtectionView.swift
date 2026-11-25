import SwiftUI
import AetherDiskCore

struct ProtectionView: View {
    @ObservedObject var model: AppModel

    private var palette: ModuleStagePalette {
        ModuleStagePalette.forPage("protection")
    }

    var body: some View {
        let report = model.protectionReport
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                protectionMetric(
                    title: "后台启动代理与守护项",
                    value: report.map { "\($0.launchItems.count) 项" } ?? "采样中…",
                    caption: report.map { "含 \($0.thirdPartyLaunchCount) 项第三方代理 · 纯只读审计" } ?? "LaunchAgents / LaunchDaemons",
                    symbol: "bolt.shield.fill",
                    tint: palette.primary
                )
                protectionMetric(
                    title: "核心安全保护防线",
                    value: "\((report?.vaultShields.count ?? 5) + model.protectedPaths.count) 重",
                    caption: "源码 · Git · 凭据 · 应用与安装包自动锁止",
                    symbol: "lock.shield.fill",
                    tint: DiskTheme.teal
                )
                protectionMetric(
                    title: "下载目录安装包核查",
                    value: report.map { "\($0.downloadInstallers.count) 个" } ?? "0 个",
                    caption: report.map { "共 \(DiskFormat.bytes($0.totalInstallerBytes)) · 默认免删保护" } ?? "~/Downloads 安装镜像",
                    symbol: "opticaldiscdrive.fill",
                    tint: palette.secondary
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(palette.primary)
                Text("只读守护承诺：安全保护模块仅通过目录元数据核查系统启动代理、隐私授权与保护防线，绝不读取任何私钥或配置文件内容，绝不擅自禁用或删除系统启动项。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.refreshSystemTelemetry()
                } label: {
                    Label("重新核查", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .accessibilityIdentifier("protection-refresh")
            }

            HStack(alignment: .top, spacing: 14) {
                tabSidebar
                    .frame(width: 204)

                switch model.protectionTab {
                case .launchItems:
                    launchItemsPane
                        .frame(maxWidth: .infinity)
                case .vaultShields:
                    vaultShieldsPane
                        .frame(maxWidth: .infinity)
                case .installers:
                    installersPane
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func protectionMetric(title: String, value: String, caption: String, symbol: String, tint: Color) -> some View {
        Surface(padding: 13) {
            HStack(alignment: .top, spacing: 11) {
                ModuleIconBadge(symbol: symbol, primary: tint, secondary: tint.opacity(0.75), size: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(caption).font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tabSidebar: some View {
        let report = model.protectionReport
        return Surface(padding: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("安全与隐私维度")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                    .accessibilityIdentifier("protection-tab-rail")

                ForEach(ProtectionTabMode.allCases) { tab in
                    let selected = model.protectionTab == tab
                    let count: Int = {
                        switch tab {
                        case .launchItems: return report?.launchItems.count ?? 0
                        case .vaultShields: return (report?.vaultShields.count ?? 5) + model.protectedPaths.count
                        case .installers: return report?.downloadInstallers.count ?? 0
                        }
                    }()
                    let icon: String = {
                        switch tab {
                        case .launchItems: return "gearshape.2.fill"
                        case .vaultShields: return "lock.shield.fill"
                        case .installers: return "shippingbox.fill"
                        }
                    }()

                    Button {
                        model.protectionTab = tab
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(selected ? palette.primary : .secondary)
                                .frame(width: 22, height: 22)
                                .background(
                                    (selected ? palette.primary : Color.primary).opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                            Text(tab.title)
                                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                            Spacer(minLength: 4)
                            Text("\(count)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(selected ? palette.primary : .secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            selected ? palette.primary.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("protection-tab-" + tab.rawValue)
                }
            }
        }
    }

    private var launchItemsPane: some View {
        let items = model.filteredLaunchItems
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                PanelTitle(
                    title: "后台启动代理与系统守护项（只读清单）",
                    caption: "共 \(items.count) 项 · 第三方项优先展示"
                )

                HStack(spacing: 8) {
                    DiskSearchField(placeholder: "搜索启动代理名称或厂商标识", text: $model.protectionQuery, identifier: "protection-search")
                    Picker("作用域", selection: $model.protectionScopeFilter) {
                        Text("全部位置").tag(nil as LaunchItemScope?)
                        ForEach(LaunchItemScope.allCases) { scope in
                            Text(scope.title).tag(Optional(scope))
                        }
                    }
                    .frame(width: 156)
                    .accessibilityIdentifier("protection-scope-picker")
                }

                if items.isEmpty {
                    Text("当前筛选条件下未检测到启动代理配置文件。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                } else {
                    ForEach(items.prefix(60)) { item in
                        DiskInteractiveRow(horizontalPadding: 8, verticalPadding: 8) {
                            HStack(spacing: 11) {
                                Image(systemName: item.isAppleSystem ? "apple.logo" : "bolt.horizontal.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(item.isAppleSystem ? Color.secondary : palette.primary)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        (item.isAppleSystem ? Color.secondary : palette.primary).opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.name)
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                        Tag(
                                            text: item.isAppleSystem ? "Apple 系统" : "第三方 · \(item.vendorLabel)",
                                            color: item.isAppleSystem ? .secondary : palette.primary
                                        )
                                        Tag(text: item.scope.title, color: DiskTheme.accent)
                                    }
                                    Text(DiskFormat.compactPath(item.path))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 8)
                                if let ts = item.modifiedAt {
                                    Text(Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                Button("在 Finder 中查看") {
                                    model.reveal(item.path)
                                }
                                .buttonStyle(DiskButtonStyle(kind: .quiet))
                                .controlSize(.small)
                            }
                        }
                        Divider().opacity(0.55)
                    }
                }
            }
        }
    }

    private var vaultShieldsPane: some View {
        let vaults = model.protectionReport?.vaultShields ?? []
        return Surface {
            VStack(alignment: .leading, spacing: 14) {
                PanelTitle(title: "隐私访问授权与防误删保护防线", caption: "清理引擎强制执行")

                HStack(spacing: 12) {
                    ModuleIconBadge(
                        symbol: model.fullDiskAccessGranted ? "checkmark.shield.fill" : "hand.raised.shield.fill",
                        primary: model.fullDiskAccessGranted ? palette.primary : .orange,
                        secondary: palette.secondary,
                        size: 34
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("macOS 完整磁盘访问权限")
                                .font(.system(size: 13, weight: .semibold))
                            Tag(
                                text: model.fullDiskAccessGranted ? "已授权" : "受限",
                                color: model.fullDiskAccessGranted ? DiskTheme.teal : .orange
                            )
                        }
                        Text(model.fullDiskAccessGranted
                             ? "应用可只读统计 Safari、Mail 等隐私容器目录大小，绝不读取文件内容。"
                             : "未授权时受限目录会明确标记为未读取路径，绝不当作 0 字节统计。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("系统隐私设置…") {
                        model.permissions()
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                ForEach(vaults) { shield in
                    HStack(spacing: 11) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(DiskTheme.teal)
                            .frame(width: 28, height: 28)
                            .background(DiskTheme.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(shield.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Tag(text: shield.exists ? "本机已开启保护" : "规则待命保护", color: DiskTheme.teal)
                            }
                            Text(shield.shieldReason)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(DiskFormat.compactPath(shield.path))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.55)
                }

                HStack {
                    Text("自定义保护目录（已配置 \(model.protectedPaths.count) / 50 项）")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("添加保护目录…") {
                        model.chooseProtectedFolder()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var installersPane: some View {
        let installers = model.protectionReport?.downloadInstallers ?? []
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                PanelTitle(
                    title: "个人下载目录安装包核查（~/Downloads）",
                    caption: "\(installers.count) 个镜像/安装包 · 自动免删保护"
                )
                Text("根据安全红线，所有 .dmg / .pkg / .iso / .xip 安装镜像默认受保护，绝不纳入自动缓存清理。你可通过快速预览核对后在 Finder 中自行归档或管理。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)

                if installers.isEmpty {
                    Text("~/Downloads 根目录下暂未发现磁盘映像或安装包文件。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                } else {
                    ForEach(installers) { item in
                        DiskInteractiveRow(horizontalPadding: 8, verticalPadding: 8) {
                            HStack(spacing: 11) {
                                Image(systemName: "opticaldiscdrive.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(palette.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(palette.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.name)
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                        Tag(text: "安装包保护", color: DiskTheme.teal)
                                    }
                                    Text(DiskFormat.compactPath(item.path))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(DiskFormat.bytes(item.allocated))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Button("快速预览") {
                                    model.quickLook(item.path)
                                }
                                .buttonStyle(DiskButtonStyle(kind: .quiet))
                                .controlSize(.small)
                                Button("在 Finder 中显示") {
                                    model.reveal(item.path)
                                }
                                .buttonStyle(DiskButtonStyle(kind: .quiet))
                                .controlSize(.small)
                            }
                        }
                        Divider().opacity(0.55)
                    }
                }
            }
        }
    }
}
