import SwiftUI
import AppKit
import CryptoKit
import UniformTypeIdentifiers
import AetherDiskCore

@MainActor
final class AppModel: ObservableObject {
    @Published var protectedPaths = UserDefaults.standard.stringArray(forKey: "ProtectedPaths") ?? []
    @Published var largeQuery = ""
    @Published var largeCategory: FileCategory?
    @Published var largeMinimum: Int64 = 100 * 1024 * 1024
    @Published var largeBasis: SizeBasis = .allocated
    @Published var largeStaleDays = 0
    @Published var rankingSort: RankingSort = .allocated
    @Published var browsePath: String?
    @Published var suggestionFilter: SuggestionFilter = .all
    @Published var suggestionCategory: CacheCategory?
    @Published var suggestionQuery = ""
    @Published var suggestionStaleOnly = false
    @Published var comparisonDepth: ComparisonDepth = .top
    @Published var comparisonDirection: ChangeDirection = .all
    @Published var comparisonQuery = ""
    @Published var projectSort: ProjectSort = .allocated
    @Published var projectQuery = ""
    @Published var rankingLimit = 40
    @Published var showIssues = false
    @Published var exporting = false
    @Published var page = "overview"
    @Published var root = FileManager.default.homeDirectoryForCurrentUser
    @Published var result: ScanResult?
    @Published var previous: ScanResult?
    @Published var history: [ScanResult] = []
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
    private var presentingPanel = false
    var recommendations: [Recommendation] {
        (result?.recommendations ?? []).map { r in var value = r; value.node = UserProtection.apply(r.node, paths: protectedPaths); return value }
    }
    var filteredRecommendations: [Recommendation] {
        RecommendationQuery.rows(recommendations, filter: suggestionFilter, category: suggestionCategory, query: suggestionQuery, staleOnly: suggestionStaleOnly)
    }
    var staleEligibleCacheIDs: Set<String> {
        RecommendationQuery.staleEligibleIDs(recommendations)
    }
    func selectStaleEligibleCaches() {
        guard fresh, !scanning, !checking else { return }
        selectedCaches.formUnion(staleEligibleCacheIDs)
    }
    var recommendationCategoryTotals: [(category: CacheCategory, allocated: Int64, count: Int)] {
        RecommendationQuery.categoryTotals(recommendations)
    }
    var projects: [ProjectSummary] {
        let raw = (result?.analysis?.projects ?? []).map { p -> ProjectSummary in
            var copy = p
            if UserProtection.overlaps(p.path, protectedPaths: protectedPaths) { copy.protection.insert(.user) }
            return copy
        }
        return ProjectWorkspaceQuery.rows(raw, sort: projectSort, query: projectQuery)
    }
    func selectProjectCaches(_ project: ProjectSummary) {
        for path in project.cachePaths where recommendations.first(where: { $0.id == path })?.blocked == false {
            selectedCaches.insert(path)
        }
        page = "suggestions"
    }
    func browseProject(_ project: ProjectSummary) {
        if let result, HierarchyBrowser.canBrowse(.init(path: project.path, kind: .directory), in: result) {
            page = "overview"
            browse(project.path)
        } else if let result, result.nodes.contains(where: { $0.path == project.path }) {
            page = "overview"
            let parent = URL(fileURLWithPath: project.path).deletingLastPathComponent().path
            browse(parent == result.root ? nil : parent)
            selectedPath = project.path
        } else {
            reveal(project.path)
        }
    }
    var activeScope: String { browsePath ?? (result?.root ?? root.path) }
    var isBrowsingSubfolder: Bool {
        guard let browsePath, let root = result?.root else { return false }
        return browsePath != root
    }
    var breadcrumbs: [(name: String, path: String)] {
        guard let root = result?.root else { return [] }
        return HierarchyBrowser.breadcrumbs(root: root, current: activeScope)
    }
    func canBrowse(_ node: DiskNode) -> Bool { HierarchyBrowser.canBrowse(node, in: result) }
    func browse(_ path: String?) {
        guard let result else { return }
        let target = path.map { URL(fileURLWithPath: $0).standardizedFileURL.path } ?? result.root
        browsePath = (target == result.root || !target.hasPrefix(result.root == "/" ? "/" : result.root + "/")) ? nil : target
        query = ""; rankingLimit = 40
        selectedPath = rows.first?.path
    }
    var largeFiles: [DiskNode] { LargeFileQuery.rows(result?.analysis?.largeFiles ?? [], query: largeQuery, category: largeCategory, minimum: largeMinimum, basis: largeBasis, staleDays: largeStaleDays).map { UserProtection.apply($0, paths: protectedPaths) } }
    func protectedNode(_ node: DiskNode) -> DiskNode { UserProtection.apply(node, paths: protectedPaths) }
    func addProtection(_ path: String) {
        guard !checking, protectedPaths.count < 50 else { return }
        let value = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        if !protectedPaths.contains(value) { protectedPaths.append(value); protectedPaths.sort(); persistProtection() }
    }
    func removeProtection(_ path: String) {
        guard !checking else { return }; protectedPaths.removeAll { $0 == path }; persistProtection()
    }
    private func persistProtection() {
        UserDefaults.standard.set(protectedPaths, forKey: "ProtectedPaths")
        plan = nil; selectedCaches = []
    }
    func chooseProtectedFolder() {
        guard !checking, !presentingPanel else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "保护此目录"; panel.message = "继续统计占用，但禁止清理该目录、内部文件及包含它的缓存父目录。"
        present(panel) { [weak self] response in
            if response == .OK, let url = panel.url { self?.addProtection(url.path) }
        }
    }
    func exportReport() {
        guard let result, !scanning, !exporting, !presentingPanel else { return }
        let panel = NSSavePanel(); panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first; panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "AetherDisk-扫描报告.csv"; panel.message = "导出元数据、保留的目录样本、大文件、类型汇总与未读取路径，不读取或导出文件内容。"
        exporting = true
        present(panel) { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { self.exporting = false; return }
            let paths = self.protectedPaths
            Task {
                do {
                    try await Task.detached(priority: .utility) { try ScanReport.csv(result, protectedPaths: paths).write(to: url, atomically: true, encoding: .utf8) }.value
                    self.message = "扫描报告已保存：\(url.path)"
                } catch { self.message = "导出失败：\(error.localizedDescription)" }
                self.exporting = false
            }
        }
    }
    private func present(_ panel: NSSavePanel, completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        guard !presentingPanel else { completion(.cancel); return }
        presentingPanel = true
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            guard window.attachedSheet == nil else { presentingPanel = false; completion(.cancel); return }
            panel.beginSheetModal(for: window) { response in
                Task { @MainActor in self.presentingPanel = false; completion(response) }
            }
        } else { let response = panel.runModal(); presentingPanel = false; completion(response) }
    }
    var eligible: [Recommendation] { recommendations.filter { !$0.blocked } }
    var eligibleBytes: Int64 { eligible.reduce(0) { $0 + $1.node.allocated } }
    var selectedNode: DiskNode? { (result?.nodes.first { $0.path == selectedPath } ?? progress.rootNodes.first { $0.path == selectedPath }).map(protectedNode) }
    var rows: [DiskNode] {
        let scope = activeScope
        let items = (result?.nodes ?? progress.rootNodes).filter { $0.parent == scope && $0.path != scope }
        let filtered = items.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        return rankingSort.sort(filtered)
    }
    var baselineOptions: [ScanResult] {
        history.filter { item in
            guard let current = result else { return true }
            return abs(item.scannedAt.timeIntervalSince(current.scannedAt)) > 0.001
        }
    }
    var comparisonSummary: ComparisonSummary? {
        guard let previous, let result, previous.root == result.root else { return nil }
        return ScanComparison.summary(current: result, previous: previous)
    }
    var changes: [(DiskNode, Int64)] {
        guard let previous, let result else { return [] }
        return ScanComparison.changes(current: result, previous: previous, depth: comparisonDepth, direction: comparisonDirection, query: comparisonQuery)
    }
    func delta(_ node: DiskNode) -> Int64? {
        guard previous?.root == result?.root, let old = previous?.nodes.first(where: { $0.path == node.path }) else { return nil }
        return node.allocated - old.allocated
    }
    func chooseFolder() {
        guard !checking, !presentingPanel else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "扫描此文件夹"; panel.message = "只读扫描文件大小；包含隐藏目录，不读取文件内容。"
        present(panel) { [weak self] response in
            if response == .OK, let url = panel.url { self?.start(url) }
        }
    }
    func start(_ url: URL? = nil) {
        guard !checking else { return }
        token.cancel(); worker?.cancel(); token = .init(); let thisToken = token
        generation = UUID(); let id = generation
        root = (url ?? root).standardizedFileURL; let scope = root
        query = ""; browsePath = nil; rankingLimit = 40; suggestionQuery = ""; suggestionStaleOnly = false; comparisonQuery = ""; plan = nil; showIssues = false
        volume = .read(at: root); history = loadHistory(root: root); previous = history.first
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
                if value.complete { self.saveSnapshot(value) }
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
            do { plan = try await cleanup.prepare(paths: chosen, protectedPaths: protectedPaths) }
            catch { message = error.localizedDescription }
            checking = false
        }
    }
    func confirm() {
        guard let plan, fresh, !scanning, !checking else { return }
        self.plan = nil; checking = true
        Task {
            do {
                let receipt = try await cleanup.execute(confirmedPlanID: plan.id, protectedPaths: protectedPaths)
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
    private func snapshotKey(root: URL) -> String {
        SHA256.hash(data: Data(root.path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    private func snapshotURL(root: URL) -> URL {
        storage.appendingPathComponent(snapshotKey(root: root) + ".json")
    }
    private func historyURL(root: URL) -> URL {
        storage.appendingPathComponent(snapshotKey(root: root) + "-history.json")
    }
    private func loadSnapshot(root: URL) -> ScanResult? {
        guard let data = try? Data(contentsOf: snapshotURL(root: root)) else { return nil }
        return try? JSONDecoder().decode(ScanResult.self, from: data)
    }
    private func loadHistory(root: URL) -> [ScanResult] {
        var list: [ScanResult] = []
        if let data = try? Data(contentsOf: historyURL(root: root)), let decoded = try? JSONDecoder().decode([ScanResult].self, from: data) {
            list = decoded
        }
        if let single = loadSnapshot(root: root) {
            list = ScanHistoryStore.append(single, into: list)
        }
        return list
    }
    private func saveSnapshot(_ result: ScanResult) {
        do {
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            let targetRoot = URL(fileURLWithPath: result.root)
            try JSONEncoder().encode(result).write(to: snapshotURL(root: targetRoot), options: .atomic)
            let updated = ScanHistoryStore.append(result, into: loadHistory(root: targetRoot))
            try JSONEncoder().encode(updated).write(to: historyURL(root: targetRoot), options: .atomic)
            history = updated
        } catch { message = "扫描已完成，但历史记录保存失败：\(error.localizedDescription)" }
    }
}
