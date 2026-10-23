import SwiftUI
import AppKit

enum DiskTheme {
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
        content.padding(padding).background(DiskTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(DiskTheme.line, lineWidth: 1))
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
