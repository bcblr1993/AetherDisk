import SwiftUI
import AppKit
import Combine
import Sparkle
import AetherDiskCore

@MainActor
final class AppUpdater: ObservableObject {
    @Published var ready = false
    @Published var canCheck = false
    @Published var status = "开发预览版 · 更新通道尚未开放"
    @Published var automatic = false {
        didSet { if ready { controller?.updater.automaticallyChecksForUpdates = automatic } }
    }
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    var releaseLabel: String { Bundle.main.object(forInfoDictionaryKey: "AetherDiskRelease") as? Bool == true ? "正式版" : "开发预览" }
    init() {
        let config = UpdateConfiguration(feed: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "", publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "")
        guard config.valid else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        do {
            try controller.updater.start()
            controller.updater.clearFeedURLFromUserDefaults()
            controller.updater.sendsSystemProfile = false
            controller.updater.automaticallyDownloadsUpdates = false
            ready = true; automatic = controller.updater.automaticallyChecksForUpdates
            canCheck = controller.updater.canCheckForUpdates; status = "更新检查已就绪 · 安装前验证签名"
            observation = controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).sink { [weak self] value in
                Task { @MainActor in self?.canCheck = value }
            }
        } catch {
            status = "更新配置未通过校验，请使用正式安装包或联系支持。"
            let detail = error as NSError
            NSLog("AetherDisk updater configuration rejected: %@ (%ld)", detail.domain, detail.code)
        }
    }
    func check() {
        guard ready, canCheck, let controller else {
            let alert = NSAlert(); alert.messageText = "当前为开发预览版"; alert.informativeText = "正式更新通道尚未开放。开放后可在应用内检查、下载并安装已签名的更新。"; alert.addButton(withTitle: "知道了"); alert.runModal(); return
        }
        controller.checkForUpdates(nil)
    }
}
struct DiskSettings: View {
    @ObservedObject var updater: AppUpdater
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) { BrandMark(size: 44); VStack(alignment: .leading, spacing: 5) { Text("AetherDisk").font(.system(size: 21, weight: .semibold)); Text("版本 \(updater.version)").font(.system(size: 12)).foregroundStyle(.secondary) } }
            Surface { VStack(alignment: .leading, spacing: 15) {
                PanelTitle(title: "应用内更新")
                Text(updater.status).font(.system(size: 12)).foregroundStyle(.secondary)
                Toggle("自动检查更新", isOn: $updater.automatic).disabled(!updater.ready)
                Text("每日检查一次。发现新版本后由你决定安装，不自动下载，不发送系统概况。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                Button("检查更新…") { updater.check() }.disabled(updater.ready && !updater.canCheck)
            } }
            Surface { VStack(alignment: .leading, spacing: 12) {
                PanelTitle(title: "自定义保护", caption: "\(model.protectedPaths.count) / 50")
                Text("目录仍参与占用统计；清理时保护该目录、其内部文件和包含它的缓存父目录。").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(model.protectedPaths, id: \.self) { path in HStack {
                    Text(DiskFormat.compactPath(path)).font(.system(size: 11)).lineLimit(2).textSelection(.enabled).help(path)
                    Spacer(); Button("移除") { model.removeProtection(path) }.disabled(model.checking).accessibilityLabel("移除保护 " + path)
                } }
                Button("添加保护目录…") { model.chooseProtectedFolder() }.disabled(model.checking || model.protectedPaths.count >= 50).accessibilityIdentifier("add-protection")
            } }
            Label("扫描记录保存在本机，清理前始终需要确认。", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(26).frame(width: 490).background(DiskTheme.background)
    }
}
