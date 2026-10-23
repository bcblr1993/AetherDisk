import SwiftUI
import AppKit
import CryptoKit
import AetherDiskCore

@MainActor
final class AppModel: ObservableObject {
    @Published var page = "overview"
    @Published var root = FileManager.default.homeDirectoryForCurrentUser
    @Published var result: ScanResult?
    @Published var previous: ScanResult?
    @Published var progress = ScanProgress()
    @Published var scanning = false
    @Published var fresh = false
    @Published var selectedPath: String?
    @Published var selectedCaches: Set<String> = []
    @Published var query = ""
    @Published var message: String?
    @Published var plan: CleanupPlan?
    @Published var checking = false
    @Published var volume = VolumeSpace.read(at: FileManager.default.homeDirectoryForCurrentUser)
    private var token = ScanCancellation()
    private var generation = UUID()
    private let cleanup = CleanupService()
    private var worker: Task<Void, Never>?
    var recommendations: [Recommendation] { result?.recommendations ?? [] }
    var eligible: [Recommendation] { recommendations.filter { !$0.blocked } }
    var eligibleBytes: Int64 { eligible.reduce(0) { $0 + $1.node.allocated } }
    var selectedNode: DiskNode? { result?.nodes.first { $0.path == selectedPath } ?? progress.rootNodes.first { $0.path == selectedPath } }
    var rows: [DiskNode] {
        let scope = result?.root ?? root.path
        let items = (result?.nodes ?? progress.rootNodes).filter { $0.parent == scope && $0.path != scope }
        return items.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { $0.allocated > $1.allocated }
    }
    var changes: [(DiskNode, Int64)] {
        guard let previous, let result else { return [] }
        return ScanComparison.changes(current: result, previous: previous)
    }
    func delta(_ node: DiskNode) -> Int64? {
        guard previous?.root == result?.root, let old = previous?.nodes.first(where: { $0.path == node.path }) else { return nil }
        return node.allocated - old.allocated
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "扫描此文件夹"; panel.message = "只读扫描文件大小；包含隐藏目录，不读取文件内容。"
        if panel.runModal() == .OK, let url = panel.url { start(url) }
    }
    func start(_ url: URL? = nil) {
        token.cancel(); worker?.cancel(); token = .init(); let thisToken = token
        generation = UUID(); let id = generation
        root = (url ?? root).standardizedFileURL; let scope = root
        volume = .read(at: root); previous = loadSnapshot(root: root)
        result = nil; scanning = true; fresh = false; selectedCaches = []; selectedPath = nil; message = nil; progress = .init()
        let updateHandler: @Sendable (ScanProgress) -> Void = { [weak self] update in
            guard let self else { return }
            Task { @MainActor in
                guard self.generation == id else { return }; self.progress = update
            }
        }
        worker = Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) { () -> Result<ScanResult, Error> in
                do {
                    return .success(try DiskScanner.scan(root: scope, cancellation: thisToken, progress: updateHandler))
                } catch { return .failure(error) }
            }.value
            guard let self, self.generation == id else { return }
            self.scanning = false
            switch outcome {
            case .success(let value):
                self.result = value; self.fresh = !value.cancelled
                self.selectedPath = value.nodes.first { $0.parent == scope.path }?.path
                if !value.cancelled { self.saveSnapshot(value) }
            case .failure(let error): self.message = error.localizedDescription
            }
            self.volume = .read(at: scope)
        }
    }
    func cancel() { token.cancel() }
    func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    func permissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
    func preview(paths: [String]? = nil) {
        guard fresh && !scanning && !checking else { return }
        let chosen = paths ?? Array(selectedCaches)
        checking = true; message = nil
        Task {
            do { plan = try await cleanup.prepare(paths: chosen) }
            catch { message = error.localizedDescription }
            checking = false
        }
    }
    func confirm() {
        guard let plan else { return }
        self.plan = nil; checking = true
        Task {
            do {
                let receipt = try await cleanup.execute(confirmedPlanID: plan.id)
                let text = "已移入废纸篓 \(receipt.moved.count) 项。可用空间变化 \(receipt.freeSpaceChange < 0 ? "−" : "+")\(DiskFormat.bytes(receipt.freeSpaceChange))。清空废纸篓后才会释放文件占用。"
                message = receipt.failed.isEmpty ? text : text + "\n未完成：" + receipt.failed.joined(separator: "\n")
                fresh = false; selectedCaches = []; volume = .read(at: root)
            } catch { message = error.localizedDescription }
            checking = false
        }
    }
    private var storage: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AetherDisk/Scans", isDirectory: true)
    }
    private func snapshotURL(root: URL) -> URL {
        let key = SHA256.hash(data: Data(root.path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return storage.appendingPathComponent(key + ".json")
    }
    private func loadSnapshot(root: URL) -> ScanResult? {
        guard let data = try? Data(contentsOf: snapshotURL(root: root)) else { return nil }
        return try? JSONDecoder().decode(ScanResult.self, from: data)
    }
    private func saveSnapshot(_ result: ScanResult) {
        do {
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            try JSONEncoder().encode(result).write(to: snapshotURL(root: URL(fileURLWithPath: result.root)), options: .atomic)
        } catch { message = "扫描已完成，但历史记录保存失败：\(error.localizedDescription)" }
    }
}
