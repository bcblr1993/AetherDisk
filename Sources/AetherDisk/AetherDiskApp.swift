import SwiftUI
import AppKit
import AetherDiskCore

@main
struct AetherDiskApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = AppUpdater()
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--appearance"), args.count > i + 1 { NSApplication.shared.appearance = NSAppearance(named: args[i + 1] == "dark" ? .darkAqua : .aqua) }
    }
    var body: some Scene {
        WindowGroup {
            ContentView(model: model, updater: updater)
                .task { await runQAIfRequested() }
        }
        .defaultSize(width: 1210, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) { Button("检查更新…") { updater.check() }.disabled(updater.ready && !updater.canCheck) }
            CommandGroup(after: .newItem) { Button("选择扫描文件夹…") { model.chooseFolder() }.keyboardShortcut("o"); Button("重新扫描") { model.start() }.keyboardShortcut("r").disabled(model.scanning); Button("导出扫描报告…") { model.exportReport() }.disabled(model.result == nil || model.scanning || model.exporting); Button("停止扫描") { model.cancel() }.disabled(!model.scanning) }
        }
        Settings { ScrollView { DiskSettings(updater: updater, model: model) }.frame(width: 550, height: 620) }
    }
    @MainActor private func runQAIfRequested() async {
        let args = CommandLine.arguments
        guard ProcessInfo.processInfo.environment["AETHERDISK_QA"] == "1", let i = args.firstIndex(of: "--qa-root"), args.count > i + 1 else { return }
        model.start(URL(fileURLWithPath: args[i + 1]))
        while model.scanning { try? await Task.sleep(for: .milliseconds(100)) }
        if let j = args.firstIndex(of: "--qa-page"), args.count > j + 1 { model.page = args[j + 1] }
        if args.contains("--qa-preview"), let first = model.eligible.first {
            model.preview(paths: [first.id]); while model.checking { try? await Task.sleep(for: .milliseconds(100)) }
        }
        if let j = args.firstIndex(of: "--qa-output"), args.count > j + 1 {
            try? await Task.sleep(for: .milliseconds(900))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }), let view = (window.attachedSheet ?? window).contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: args[j + 1])) }
            if let result = model.result { try? JSONEncoder().encode(result).write(to: URL(fileURLWithPath: args[j + 1] + ".scan.json")) }
        }
    }
}
