import SwiftUI
import AppKit
import AetherDiskCore

@main
struct AetherDiskApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = AppUpdater()
    @State private var menuBarInserted: Bool = (ProcessInfo.processInfo.environment["AETHERDISK_QA"] != "1")

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--appearance"), args.count > i + 1 {
            NSApplication.shared.appearance = NSAppearance(named: args[i + 1] == "dark" ? .darkAqua : .aqua)
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(model: model, updater: updater)
                .task { await runQAIfRequested() }
        }
        .defaultSize(width: 1260, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { updater.check() }
                    .disabled(updater.ready && !updater.canCheck)
            }
            CommandGroup(after: .newItem) {
                Button("选择扫描文件夹…") { model.chooseFolder() }.keyboardShortcut("o")
                Button("重新扫描") { model.start() }.keyboardShortcut("r").disabled(model.scanning)
                Button("导出扫描报告…") { model.exportReport() }.disabled(model.result == nil || model.scanning || model.exporting)
                Button("停止扫描") { model.cancel() }.disabled(!model.scanning)
                Divider()
                Button("智能护理") { model.page = "smartcare" }.keyboardShortcut("1", modifiers: .command)
                Button("系统清理") { if !model.isExternalVolume { model.page = "suggestions" } }.keyboardShortcut("2", modifiers: .command)
                Button("安全保护") { model.page = "protection" }.keyboardShortcut("3", modifiers: .command)
                Button("性能优化") { model.page = "performance" }.keyboardShortcut("4", modifiers: .command)
                Button("应用管理") { model.page = "applications" }.keyboardShortcut("5", modifiers: .command)
                Button("我的杂物") { model.page = "large" }.keyboardShortcut("6", modifiers: .command)
                Button("空间透镜") { model.page = "overview" }.keyboardShortcut("7", modifiers: .command)
                Divider()
                Button("返回上一级") { model.navigateUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(!model.isBrowsingSubfolder || model.scanning)
                Button("快速预览所选文件") {
                    if let node = model.selectedNode, node.kind == .file {
                        model.quickLook(node.path)
                    }
                }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(model.selectedNode?.kind != .file)
            }
        }

        MenuBarExtra("AetherDisk", systemImage: "internaldrive.fill", isInserted: $menuBarInserted) {
            MenuBarHealthPopoverView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            ScrollView { DiskSettings(updater: updater, model: model).padding(16) }
                .frame(width: 560, height: 640)
                .background(DiskTheme.background)
        }
    }

    @MainActor private func runQAIfRequested() async {
        let args = CommandLine.arguments
        guard ProcessInfo.processInfo.environment["AETHERDISK_QA"] == "1",
              let i = args.firstIndex(of: "--qa-root"),
              args.count > i + 1 else { return }
        if let j = args.firstIndex(of: "--qa-page"), args.count > j + 1 {
            model.page = args[j + 1]
        }
        let requestedSubTabArg: String? = {
            guard let s = args.firstIndex(of: "--qa-subtab"), args.count > s + 1 else { return nil }
            return args[s + 1]
        }()
        if model.page == "suggestions", let requestedSubTabArg,
           let requestedSubTab = CleanupSubTab(rawValue: requestedSubTabArg) {
            model.cleanupSubTab = requestedSubTab
        } else if model.page == "large", let requestedSubTabArg,
                  let requestedClutterTab = ClutterSubTab(rawValue: requestedSubTabArg) {
            model.clutterTab = requestedClutterTab
            model.showDuplicateSuspects = (requestedClutterTab == .duplicates)
        }
        if let m = args.firstIndex(of: "--qa-view-mode"), args.count > m + 1,
           let mode = OverviewVisualMode(rawValue: args[m + 1]) {
            model.overviewVisualMode = mode
        }
        model.start(URL(fileURLWithPath: args[i + 1]))
        while model.scanning { try? await Task.sleep(for: .milliseconds(100)) }
        if model.page == "suggestions", let requestedSubTabArg,
           let requestedSubTab = CleanupSubTab(rawValue: requestedSubTabArg) {
            model.cleanupSubTab = requestedSubTab
            if requestedSubTab == .cloudStorage {
                model.refreshCloudStorage()
            }
        } else if model.page == "large", let requestedSubTabArg,
                  let requestedClutterTab = ClutterSubTab(rawValue: requestedSubTabArg) {
            model.clutterTab = requestedClutterTab
            model.showDuplicateSuspects = (requestedClutterTab == .duplicates)
            if requestedClutterTab == .duplicates {
                model.syncSelectedDuplicateGroup()
            }
        }
        if args.contains("--qa-assistant") {
            model.showAssistant = true
        }
        if args.contains("--qa-preview"), let first = model.eligible.first {
            model.preview(paths: [first.id])
            while model.checking { try? await Task.sleep(for: .milliseconds(100)) }
        }
        if let j = args.firstIndex(of: "--qa-output"), args.count > j + 1 {
            if model.page == "applications" {
                while model.scanningApps { try? await Task.sleep(for: .milliseconds(80)) }
            }
            if model.page == "suggestions", model.cleanupSubTab == .cloudStorage {
                var waitedMs = 0
                while model.scanningCloud && waitedMs < 10_000 {
                    try? await Task.sleep(for: .milliseconds(80))
                    waitedMs += 80
                }
            }
            try? await Task.sleep(for: .milliseconds(900))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width >= 600 }),
                  let view = (window.attachedSheet ?? window).contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: args[j + 1]))
            }
            if let result = model.result {
                try? JSONEncoder().encode(result).write(to: URL(fileURLWithPath: args[j + 1] + ".scan.json"))
            }
        }
    }
}
