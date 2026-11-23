import SwiftUI
import AetherDiskCore

struct MillerColumnsView: View {
    let columns: [MillerColumn]
    let selectedPath: String?
    let onSelectNode: (DiskNode, String) -> Void
    let onDrillDownNode: (DiskNode) -> Void
    let onRescanNode: (DiskNode) -> Void

    init(
        columns: [MillerColumn],
        selectedPath: String?,
        onSelectNode: @escaping (DiskNode, String) -> Void,
        onDrillDownNode: @escaping (DiskNode) -> Void,
        onRescanNode: @escaping (DiskNode) -> Void
    ) {
        self.columns = columns
        self.selectedPath = selectedPath
        self.onSelectNode = onSelectNode
        self.onDrillDownNode = onDrillDownNode
        self.onRescanNode = onRescanNode
    }

    var body: some View {
        Group {
            if columns.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "sidebar.squares.leading")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("暂无可展开的目录分栏")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DiskTheme.line, lineWidth: 1))
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(columns) { column in
                                MillerColumnPane(
                                    column: column,
                                    selectedPath: selectedPath,
                                    onSelectNode: onSelectNode,
                                    onDrillDownNode: onDrillDownNode,
                                    onRescanNode: onRescanNode
                                )
                                .id(column.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: columns.last?.id) { _, lastID in
                        guard let lastID else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .trailing)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("miller-columns")
    }
}

private struct MillerColumnPane: View {
    let column: MillerColumn
    let selectedPath: String?
    let onSelectNode: (DiskNode, String) -> Void
    let onDrillDownNode: (DiskNode) -> Void
    let onRescanNode: (DiskNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DiskTheme.accent)
                Text(column.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text(DiskFormat.bytes(column.totalAllocated))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DiskTheme.surface.opacity(0.6))

            Divider().overlay(DiskTheme.line)

            if column.items.isEmpty {
                Text("空目录或权限受限")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2) {
                        ForEach(column.items) { node in
                            MillerColumnRow(
                                node: node,
                                columnPath: column.path,
                                columnTotal: column.totalAllocated,
                                isSelected: node.path == selectedPath,
                                isBranchHighlighted: node.path == column.selectedChildPath,
                                onSelectNode: onSelectNode,
                                onDrillDownNode: onDrillDownNode,
                                onRescanNode: onRescanNode
                            )
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(width: 245)
        .frame(maxHeight: .infinity)
        .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DiskTheme.line, lineWidth: 1))
    }
}

private struct MillerColumnRow: View {
    let node: DiskNode
    let columnPath: String
    let columnTotal: Int64
    let isSelected: Bool
    let isBranchHighlighted: Bool
    let onSelectNode: (DiskNode, String) -> Void
    let onDrillDownNode: (DiskNode) -> Void
    let onRescanNode: (DiskNode) -> Void

    @State private var hovering = false
    @State private var lastTapAt: Date?

    private var fraction: Double {
        guard columnTotal > 0 else { return 0 }
        return min(1.0, max(0.0, Double(node.allocated) / Double(columnTotal)))
    }

    private var iconTint: Color {
        if !node.protection.isEmpty { return .teal }
        return node.kind == .directory ? DiskTheme.accent : DiskTheme.purple
    }

    private var rowBackground: Color {
        if isSelected { return DiskTheme.accent.opacity(0.14) }
        if isBranchHighlighted { return DiskTheme.accent.opacity(0.08) }
        if hovering { return DiskTheme.accent.opacity(0.05) }
        return .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: node.kind == .directory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(iconTint)
                    .frame(width: 16)

                Text(node.name)
                    .font(.system(size: 11.5, weight: isSelected || isBranchHighlighted ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if node.restricted {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.orange)
                }
                if !node.protection.isEmpty {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.teal)
                }

                VStack(alignment: .trailing, spacing: 1) {
                    Text(DiskFormat.bytes(node.allocated))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text(String(format: "%.1f%%", fraction * 100))
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                if node.kind == .directory {
                    Button {
                        onDrillDownNode(node)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 18)
                    }
                    .buttonStyle(DiskButtonStyle(kind: .quiet))
                    .help("展开 \(node.name)")
                    .accessibilityLabel("展开 \(node.name)")
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DiskTheme.line)
                    Capsule()
                        .fill(iconTint.opacity(isSelected || isBranchHighlighted ? 0.78 : 0.45))
                        .frame(width: max(2, geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 2.5)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? DiskTheme.accent.opacity(0.45) : .clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { hovering = $0 }
        .onTapGesture {
            let now = Date()
            let isDoubleTap = lastTapAt.map { now.timeIntervalSince($0) < 0.38 } ?? false
            if node.kind == .directory && (isSelected || isDoubleTap) {
                lastTapAt = nil
                onDrillDownNode(node)
            } else {
                lastTapAt = now
                onSelectNode(node, columnPath)
            }
        }
        .contextMenu {
            if node.kind == .directory {
                Button("展开此层级") {
                    onDrillDownNode(node)
                }
                Button("再次深度扫描此文件夹") {
                    onRescanNode(node)
                }
            }
        }
    }
}
