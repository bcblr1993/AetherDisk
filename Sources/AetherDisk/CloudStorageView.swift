import SwiftUI
import AetherDiskCore

struct CloudStorageView: View {
    @ObservedObject var model: AppModel
    @State private var selectedProviderPath: String?
    @State private var selectedLocalFilePath: String?

    private var palette: ModuleStagePalette {
        ModuleStagePalette.forPage("suggestions")
    }

    private var providers: [CloudProviderSummary] {
        model.cloudReport?.providers ?? []
    }

    private var selectedProvider: CloudProviderSummary? {
        if let selectedProviderPath,
           let match = providers.first(where: { $0.path == selectedProviderPath }) {
            return match
        }
        return providers.first
    }

    private func selectedFile(in provider: CloudProviderSummary) -> CloudLocalFileItem? {
        if let selectedLocalFilePath,
           let match = provider.topLocalFiles.first(where: { $0.path == selectedLocalFilePath }) {
            return match
        }
        return provider.topLocalFiles.first
    }

    private func providerSymbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("icloud") { return "icloud.fill" }
        if lower.contains("google") { return "externaldrive.badge.icloud" }
        if lower.contains("onedrive") { return "cloud.fill" }
        if lower.contains("dropbox") { return "shippingbox.fill" }
        return "folder.badge.person.crop"
    }

    var body: some View {
        let report = model.cloudReport
        VStack(alignment: .leading, spacing: 16) {
            // Top 3 read-only summary cards (container wraps no interactive buttons so child AX identifiers stay visible)
            HStack(spacing: 12) {
                SuggestionMetricCard(
                    title: "本地实际驻留",
                    value: report.map { DiskFormat.bytes($0.totalAllocated) } ?? (model.scanningCloud ? "扫描中…" : "0 B"),
                    caption: report.map { "\($0.totalLocalFiles.formatted()) 个本地文件 · 占用本机空间" } ?? "仅统计实际已分配磁盘块",
                    icon: "internaldrive.fill",
                    tint: palette.primary
                )
                SuggestionMetricCard(
                    title: "云端占位未下载",
                    value: report.map { DiskFormat.bytes($0.totalCloudOnlyLogical) } ?? "0 B",
                    caption: report.map { "\($0.totalDatalessFiles.formatted()) 个纯云端占位文件 · 0 B 本地块" } ?? "dataless 占位逻辑体积",
                    icon: "icloud.fill",
                    tint: palette.secondary
                )
                SuggestionMetricCard(
                    title: "已识别云盘服务",
                    value: report.map { "\($0.providers.count) 项" } ?? (model.scanningCloud ? "…" : "0 项"),
                    caption: report.map { "本地 \($0.totalLocalFiles.formatted()) 项 · 逻辑总计 \(DiskFormat.bytes($0.totalLogical))" } ?? "~/Library/CloudStorage 与 iCloud",
                    icon: "cloud.fill",
                    tint: DiskTheme.teal
                )
            }
            .accessibilityIdentifier("cloud-storage-view")

            // Explicit read-only safety boundary & refresh trigger
            HStack(spacing: 9) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(DiskTheme.teal)
                Text("云盘目录仅只读透视本地驻留与云端占位，绝不触发云端下载，也绝不提供云端删除入口")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let unreadable = report?.unreadableCount, unreadable > 0 {
                    Tag(text: "\(unreadable) 个路径未能读取", color: .orange)
                }
                Spacer()
                Button {
                    model.refreshCloudStorage()
                } label: {
                    Label(model.scanningCloud ? "正在透视…" : "刷新云盘统计", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(model.scanningCloud)
                .accessibilityIdentifier("cloud-refresh-button")
            }

            if model.scanningCloud && report == nil {
                Surface(padding: 36) {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在以只读元数据方式透视云盘本地驻留与占位比例…")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if providers.isEmpty {
                emptyCloudState
            } else if let provider = selectedProvider {
                HStack(alignment: .top, spacing: 14) {
                    providerSidebar
                        .frame(width: 244)
                    providerDetailPane(provider)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var emptyCloudState: some View {
        Surface(padding: 32) {
            VStack(alignment: .center, spacing: 14) {
                ModuleIconBadge(
                    symbol: "icloud.slash.fill",
                    primary: palette.primary,
                    secondary: palette.secondary,
                    size: 56
                )
                Text("未检测到激活的本地云盘目录")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("AetherDisk 以纯元数据只读方式监测 ~/Library/CloudStorage 与 iCloud Drive（~/Library/Mobile Documents/com~apple~CloudDocs）。当前未发现云盘同步目录；接入云盘后，可在此透明对比本地实际磁盘块占用与云端 dataless 占位体积，绝不触发文件下载，也不提供任何删除入口。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 560)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var providerSidebar: some View {
        Surface(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("已识别云盘服务（\(providers.count)）")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)

                ForEach(providers) { provider in
                    let isSelected = selectedProvider?.path == provider.path
                    let totalCompare = max(Int64(1), provider.allocated + provider.cloudOnlyLogical)
                    let localRatio = CGFloat(provider.allocated) / CGFloat(totalCompare)

                    Button {
                        selectedProviderPath = provider.path
                        selectedLocalFilePath = provider.topLocalFiles.first?.path
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: providerSymbol(for: provider.name))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isSelected ? palette.primary : .secondary)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        (isSelected ? palette.primary : Color.primary).opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.name)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                        .lineLimit(1)
                                    Text("本地 \(provider.localFileCount.formatted()) · 占位 \(provider.datalessFileCount.formatted())")
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(palette.secondary.opacity(0.20))
                                    Capsule()
                                        .fill(palette.primary)
                                        .frame(width: provider.allocated > 0 ? max(4, geo.size.width * localRatio) : 0)
                                }
                            }
                            .frame(height: 4)

                            HStack {
                                Text("本地 \(DiskFormat.bytes(provider.allocated))")
                                    .foregroundStyle(isSelected ? palette.primary : .secondary)
                                Spacer()
                                Text("占位 \(DiskFormat.bytes(provider.cloudOnlyLogical))")
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? palette.primary.opacity(0.11) : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(isSelected ? palette.primary.opacity(0.24) : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func providerDetailPane(_ provider: CloudProviderSummary) -> some View {
        let activeFile = selectedFile(in: provider)
        let combined = max(Int64(1), provider.allocated + provider.cloudOnlyLogical)
        let localFraction = Double(provider.allocated) / Double(combined)
        let cloudFraction = Double(provider.cloudOnlyLogical) / Double(combined)

        return Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    ModuleIconBadge(
                        symbol: providerSymbol(for: provider.name),
                        primary: palette.primary,
                        secondary: palette.secondary,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(provider.name)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Tag(text: "纯只读透视", color: DiskTheme.teal)
                        }
                        Text(DiskFormat.compactPath(provider.path))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(provider.path)
                    }
                    Spacer()
                    Button("在 Finder 中显示") {
                        model.reveal(provider.path)
                    }
                    .buttonStyle(DiskButtonStyle(kind: .secondary))
                    .controlSize(.small)
                }

                // Breakdown bar comparing local resident allocated bytes vs cloud-only dataless logical bytes
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("本地驻留 vs 云端占位空间分布")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("逻辑总计 \(DiskFormat.bytes(provider.logical))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    GeometryReader { geo in
                        let hasAny = provider.allocated > 0 || provider.cloudOnlyLogical > 0
                        HStack(spacing: 2) {
                            if !hasAny {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(DiskTheme.line)
                            } else {
                                if provider.allocated > 0 {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(LinearGradient(colors: [palette.primary, DiskTheme.accent], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(6, geo.size.width * CGFloat(localFraction)))
                                }
                                if provider.cloudOnlyLogical > 0 {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(palette.secondary.opacity(0.45))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    .frame(height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 10) {
                        breakdownLegendPill(
                            color: palette.primary,
                            title: "本地实际驻留",
                            value: DiskFormat.bytes(provider.allocated),
                            detail: "\(provider.localFileCount.formatted()) 个文件 · \(Int((localFraction * 100).rounded()))%"
                        )
                        breakdownLegendPill(
                            color: palette.secondary.opacity(0.65),
                            title: "云端占位未下载",
                            value: DiskFormat.bytes(provider.cloudOnlyLogical),
                            detail: "\(provider.datalessFileCount.formatted()) 个 dataless 文件 · \(Int((cloudFraction * 100).rounded()))%"
                        )
                    }

                    if provider.unreadableCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("该目录有 \(provider.unreadableCount) 个权限受限子项未能读取，数值可能低于云盘全量。")
                                .foregroundStyle(.orange)
                        }
                        .font(.system(size: 10.5))
                    }
                }
                .padding(12)
                .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius, style: .continuous))

                Divider().opacity(0.55)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本地驻留体积前列文件")
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        Text("仅展示已驻留本地（allocated > 0）的前 \(provider.topLocalFiles.count) 项 · 绝不触碰纯云端占位文件")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let activeFile {
                        Button {
                            model.quickLook(activeFile.path)
                        } label: {
                            Label("快速预览所选 (⌘Y)", systemImage: "eye")
                        }
                        .buttonStyle(DiskButtonStyle(kind: .secondary))
                        .controlSize(.small)
                        .keyboardShortcut("y", modifiers: .command)
                        .help("使用系统 Quick Look 只读预览 \(activeFile.name) (⌘Y)")
                    }
                }

                if provider.topLocalFiles.isEmpty {
                    Text("该云盘目录下暂未发现占用本地磁盘块的文件（可能均为云端按需占位文件）。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 28)
                } else {
                    VStack(spacing: 0) {
                        ForEach(provider.topLocalFiles) { file in
                            let isFileSelected = activeFile?.path == file.path
                            DiskInteractiveRow(selected: isFileSelected, horizontalPadding: 8, verticalPadding: 9) {
                                HStack(alignment: .center, spacing: 11) {
                                    Image(systemName: "doc.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(palette.primary)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            palette.primary.opacity(0.10),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        )
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(file.name)
                                                .font(.system(size: 12.5, weight: .semibold))
                                                .lineLimit(1)
                                            Tag(text: "本地驻留", color: DiskTheme.teal)
                                        }
                                        Text(DiskFormat.compactPath(file.path))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help(file.path)
                                    }
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(DiskFormat.bytes(file.allocated))
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .monospacedDigit()
                                        if file.logical > file.allocated {
                                            Text("逻辑 \(DiskFormat.bytes(file.logical))")
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(.secondary)
                                                .monospacedDigit()
                                        } else if file.modifiedAt > 0 {
                                            Text(Date(timeIntervalSince1970: TimeInterval(file.modifiedAt)).formatted(date: .abbreviated, time: .omitted))
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    HStack(spacing: 6) {
                                        Button("快速预览") {
                                            selectedLocalFilePath = file.path
                                            model.quickLook(file.path)
                                        }
                                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                                        .controlSize(.small)
                                        .accessibilityLabel("快速预览 " + file.name)

                                        Button("在 Finder 中显示") {
                                            selectedLocalFilePath = file.path
                                            model.reveal(file.path)
                                        }
                                        .buttonStyle(DiskButtonStyle(kind: .quiet))
                                        .controlSize(.small)
                                        .accessibilityLabel("在 Finder 中显示 " + file.name)
                                    }
                                }
                            }
                            .onTapGesture {
                                selectedLocalFilePath = file.path
                            }
                            .contextMenu {
                                Button("快速预览") { model.quickLook(file.path) }
                                Button("在 Finder 中显示") { model.reveal(file.path) }
                                Button("复制路径") { model.copyPath(file.path) }
                            }

                            if file.id != provider.topLocalFiles.last?.id {
                                Divider().opacity(0.55)
                            }
                        }
                    }
                }
            }
        }
    }

    private func breakdownLegendPill(color: Color, title: String, value: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DiskTheme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
