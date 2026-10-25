import SwiftUI
import AppKit

enum DiskTheme {
    static let filledAccent = Color(light: 0x3A5BD9, dark: 0x506AE0)
    static let filledDanger = Color(light: 0xC13D45, dark: 0xB9424C)
    static let controlRadius: CGFloat = 8
    static let cardRadius: CGFloat = 14
    static let danger = Color(light: 0xC94449, dark: 0xE3666C)
    static let accent = Color(light: 0x3A5BD9, dark: 0x6F8CFF)
    static let purple = Color(light: 0x7253CF, dark: 0xA58BFF)
    static let background = Color(light: 0xF5F5F7, dark: 0x111113)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1B1B1F)
    static let inset = Color(light: 0xFBFBFD, dark: 0x222227)
    static let line = Color.primary.opacity(0.075)
    static let colors: [Color] = [accent, purple, .teal, .orange, .pink, .cyan, .indigo]
}
extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}
struct BrandMark: View {
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27).fill(LinearGradient(colors: [DiskTheme.accent, DiskTheme.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().trim(from: 0.03, to: 0.76).stroke(.white.opacity(0.94), style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round)).rotationEffect(.degrees(-90)).padding(size * 0.23)
            Circle().trim(from: 0.8, to: 0.97).stroke(.white.opacity(0.48), style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round)).rotationEffect(.degrees(-90)).padding(size * 0.23)
            Circle().fill(.white).frame(width: size * 0.12, height: size * 0.12)
        }.frame(width: size, height: size)
    }
}
struct Surface<Content: View>: View {
    let content: Content
    let padding: CGFloat
    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) { self.padding = padding; self.content = content() }
    var body: some View {
        content.padding(padding).background(DiskTheme.surface, in: RoundedRectangle(cornerRadius: DiskTheme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: DiskTheme.cardRadius).stroke(DiskTheme.line, lineWidth: 1))
    }
}
struct Tag: View {
    let text: String
    var color: Color = DiskTheme.accent
    var body: some View { Text(text).font(.system(size: 10, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 4).foregroundStyle(color).background(color.opacity(0.09), in: Capsule()) }
}
struct PanelTitle: View {
    let title: String; var caption: String = ""
    var body: some View { HStack { Text(title).font(.system(size: 14, weight: .semibold)); Spacer(); if !caption.isEmpty { Text(caption).font(.system(size: 11)).foregroundStyle(.secondary) } } }
}

struct CleanupRiskNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("清理风险提示", systemImage: "exclamationmark.triangle").font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
            Text("软件及清理建议可能存在问题或误判，请谨慎操作。重要文件请先备份，并逐项核对清理目录。误删或数据丢失由用户自行承担，开发者概不负责。")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine).accessibilityIdentifier("cleanup-risk-notice")
    }
}

// Shared control hierarchy for every application-owned page and sheet.
enum DiskButtonKind { case primary, secondary, quiet }
struct DiskButtonStyle: ButtonStyle {
    var kind: DiskButtonKind = .secondary
    func makeBody(configuration: Configuration) -> some View {
        DiskButtonChrome(configuration: configuration, kind: kind)
    }
}
private struct DiskButtonChrome: View {
    let configuration: ButtonStyleConfiguration
    let kind: DiskButtonKind
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size
    @Environment(\.isFocused) private var focused
    @State private var hovering = false
    private var tint: Color { configuration.role == .destructive ? DiskTheme.danger : DiskTheme.accent }
    private var small: Bool { size == .small || size == .mini }
    private var foreground: Color { kind == .primary ? .white : kind == .quiet ? tint : .primary }
    private var fill: Color {
        if kind == .primary { return (configuration.role == .destructive ? DiskTheme.filledDanger : DiskTheme.filledAccent).opacity(configuration.isPressed ? 0.82 : hovering ? 0.92 : 1) }
        if hovering || configuration.isPressed { return tint.opacity(configuration.isPressed ? 0.12 : 0.065) }
        return kind == .secondary ? DiskTheme.surface : .clear
    }
    var body: some View {
        configuration.label.font(.system(size: small ? 11 : 12, weight: .medium))
            .padding(.horizontal, small ? 9 : 12).frame(minHeight: small ? 26 : 32)
            .foregroundStyle(foreground).background(fill, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DiskTheme.controlRadius).stroke(kind == .secondary ? DiskTheme.line : .clear, lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: DiskTheme.controlRadius + 2).stroke(focused ? DiskTheme.accent.opacity(0.6) : .clear, lineWidth: 2).padding(-3))
            .contentShape(RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
            .opacity(enabled ? 1 : 0.4).onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
struct DiskSidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(DiskTheme.accent.opacity(configuration.isPressed ? 0.09 : 0), in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
    }
}
struct DiskDialog<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    var destructive = false
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                    .foregroundStyle(destructive ? DiskTheme.danger : DiskTheme.accent)
                    .frame(width: 42, height: 42)
                    .background((destructive ? DiskTheme.danger : DiskTheme.accent).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 19, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(22)
            Divider().overlay(DiskTheme.line)
            VStack(alignment: .leading, spacing: 16) { content }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(DiskTheme.line)
            HStack(spacing: 10) { actions }.padding(.horizontal, 22).padding(.vertical, 16).background(DiskTheme.inset)
        }.frame(width: 600).background(DiskTheme.surface).tint(DiskTheme.accent)
            .buttonStyle(DiskButtonStyle())
    }
}
struct DiskSearchField: View {
    let placeholder: String
    @Binding var text: String
    var identifier = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain).focused($focused).accessibilityIdentifier(identifier)
        }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: 32)
            .background(DiskTheme.inset, in: RoundedRectangle(cornerRadius: DiskTheme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DiskTheme.controlRadius).stroke(focused ? DiskTheme.accent.opacity(0.65) : DiskTheme.line, lineWidth: 1))
    }
}
