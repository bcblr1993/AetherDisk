import XCTest
import Foundation
@testable import AetherDiskCore

final class AnalysisTests: XCTestCase, @unchecked Sendable {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("AetherDiskAnalysis-" + UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    @discardableResult func file(_ path: String, bytes: Int = 4096) throws -> URL {
        let u = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(repeating: 9, count: bytes).write(to: u); return u
    }
    func testDeepFileSurvivesDirectoryBudgetAndAllTypesStillCount() throws {
        for i in 0..<20_010 { try file("000/\(i).data", bytes: 0) }
        let big = try file("ZZDeep/a/b/movie.mp4", bytes: 2 * 1024 * 1024)
        let result = try DiskScanner.scan(root: root)
        XCTAssertEqual(result.analysis?.fileTypes.reduce(0) { $0 + $1.files }, 20_011)
        XCTAssertTrue(result.analysis?.largeFiles.contains { $0.path == big.path } == true)
        XCTAssertEqual(Set(result.nodes.map(\.path)).count, result.nodes.count)
        XCTAssertLessThan(result.nodes.count, 20_500)
    }
    func testSparseFileAppearsInLogicalRankingButNotPhysicalRanking() throws {
        let p = try file("sparse.bin", bytes: 0); let f = try FileHandle(forWritingTo: p); try f.truncate(atOffset: 256 * 1024 * 1024); try f.close()
        let result = try DiskScanner.scan(root: root); let files = result.analysis?.largeFiles ?? []
        XCTAssertTrue(LargeFileQuery.rows(files, basis: .allocated).isEmpty)
        XCTAssertEqual(LargeFileQuery.rows(files, basis: .logical).first?.path, p.path)
    }
    func testTypeCountsDeduplicateHardlinks() throws {
        let p = try file("a.mp4", bytes: 8192); try FileManager.default.linkItem(at: p, to: root.appendingPathComponent("b.mp4"))
        try file("source.swift"); try file("installer.dmg")
        let a = try XCTUnwrap(DiskScanner.scan(root: root).analysis)
        XCTAssertEqual(a.fileTypes.first { $0.category == .video }?.files, 1)
        XCTAssertEqual(a.fileTypes.first { $0.category == .source }?.logical, 4096)
        XCTAssertEqual(a.fileTypes.first { $0.category == .archive }?.files, 1)
    }
    func testBoundedTopFilesKeepPhysicalAndLogicalWinners() {
        var accumulator = AnalysisAccumulator()
        for i in 1...1500 { accumulator.record(.init(path: "/data/\(i).bin", kind: .file, allocated: Int64(i) * 1024 * 1024, logical: Int64(1501 - i) * 1024 * 1024, fileCount: 1)) }
        let result = accumulator.result()
        XCTAssertLessThanOrEqual(result.largeFiles.count, 400)
        XCTAssertEqual(LargeFileQuery.rows(result.largeFiles).first?.name, "1500.bin")
        XCTAssertEqual(LargeFileQuery.rows(result.largeFiles, basis: .logical).first?.name, "1.bin")
        XCTAssertEqual(result.fileTypes.reduce(0) { $0 + $1.files }, 1500)
    }
    func testSearchCategoryThresholdAndStableTies() {
        let files = [DiskNode(path: "/movie/B.mp4", kind: .file, allocated: 200, logical: 500), DiskNode(path: "/movie/A.mp4", kind: .file, allocated: 200, logical: 300), DiskNode(path: "/code/file.swift", kind: .file, allocated: 900, logical: 900)]
        XCTAssertEqual(LargeFileQuery.rows(files, query: "MOVIE", category: .video, minimum: 100).map(\.name), ["A.mp4", "B.mp4"])
        XCTAssertTrue(LargeFileQuery.rows(files, category: .video, minimum: 600).isEmpty)
        XCTAssertEqual(FileCategory.classify("index.ts"), .source)
    }
    func testProtectionOverlapIncludesAncestorsButNotSiblings() {
        let paths = ["/home/project/cache/keep"]
        XCTAssertTrue(UserProtection.overlaps("/home/project", protectedPaths: paths))
        XCTAssertTrue(UserProtection.overlaps("/home/project/cache/keep/child", protectedPaths: paths))
        XCTAssertFalse(UserProtection.overlaps("/home/project/cache/keeper", protectedPaths: paths))
        XCTAssertTrue(UserProtection.overlaps("/home/other/../project", protectedPaths: paths))
        XCTAssertTrue(UserProtection.overlaps("/home", protectedPaths: ["/"]))
    }
    func testRemovingUserProtectionKeepsBuiltInProtection() {
        let node = DiskNode(path: "/keep/release.dmg", kind: .file, protection: [.installer])
        let protected = UserProtection.apply(node, paths: ["/keep"])
        XCTAssertEqual(protected.protection, [.installer, .user])
        XCTAssertEqual(UserProtection.apply(protected, paths: []).protection, [.installer])
    }
    func testProtectedDescendantBlocksParentCleanup() async throws {
        let c = try file("Home/Library/Caches/Example/data").deletingLastPathComponent(); let home = root.appendingPathComponent("Home")
        let service = CleanupService(home: home, trash: { _ in XCTFail("Must preserve") }, checkUsage: { _ in })
        do { _ = try await service.prepare(paths: [c.path], protectedPaths: [c.appendingPathComponent("keep").path]); XCTFail("Protected descendant accepted") } catch {}
    }
    func testProtectionAddedAfterPreviewBlocksWholeBatch() async throws {
        let a = try file("Home/Library/Caches/A/data").deletingLastPathComponent(); let b = try file("Home/Library/Caches/B/data").deletingLastPathComponent()
        let service = CleanupService(home: root.appendingPathComponent("Home"), trash: { _ in XCTFail("Must preserve all targets") }, checkUsage: { _ in })
        let plan = try await service.prepare(paths: [a.path,b.path])
        do { _ = try await service.execute(confirmedPlanID: plan.id, protectedPaths: [b.path]); XCTFail("New protection ignored") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }
    func testLegacySnapshotDecodesWithoutAnalysis() throws {
        try file("data"); let r = try DiskScanner.scan(root: root)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any]); json.removeValue(forKey: "analysis")
        let legacy = try JSONDecoder().decode(ScanResult.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.analysis); XCTAssertEqual(legacy.root, r.root)
    }
    func testCSVQuotesAndNeutralizesSpreadsheetFormulas() {
        XCTAssertEqual(ScanReport.cell("=1+1"), "\"'=1+1\"")
        XCTAssertEqual(ScanReport.cell(" \t@SUM(A1)"), "\"' \t@SUM(A1)\"")
        XCTAssertEqual(ScanReport.cell("a,\"b\"\nc"), "\"a,\"\"b\"\"\nc\"")
    }
    func testReportIncludesPartialStatusTypesIssuesAndProtection() throws {
        let p = try file("movie.mp4", bytes: 2 * 1024 * 1024); var r = try DiskScanner.scan(root: root)
        r.unreadable = 1; r.issues = [root.appendingPathComponent("Restricted").path]
        let csv = ScanReport.csv(r, protectedPaths: [root.path])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}section,path")); XCTAssertTrue(csv.contains("\"partial\"")); XCTAssertTrue(csv.contains("\"unreadable\"")); XCTAssertTrue(csv.contains("\"file_type\"")); XCTAssertTrue(csv.contains(p.path)); XCTAssertTrue(csv.contains("\"user\""))
    }
    func testProtectionConservativelyHandlesCaseAndUnicodeAliases() {
        XCTAssertTrue(UserProtection.overlaps("/HOME/Project/KEEP/child", protectedPaths: ["/home/project/keep"]))
        XCTAssertTrue(UserProtection.overlaps("/home/Cafe\u{301}/child", protectedPaths: ["/home/Café"]))
    }

    func testExportedReportsAndDocumentsBlockCacheCleanup() throws {
        for ext in ["csv", "pdf", "md", "docx"] {
            let cache = try file("Home/Library/Caches/Report-\(ext)/AetherDisk-report.\(ext)").deletingLastPathComponent()
            XCTAssertThrowsError(try SafetyInspector.inspect(cache, home: root.appendingPathComponent("Home")))
        }
    }

    func testRankingSortHierarchyBrowserAndRecommendationQuery() throws {
        try file("Home/Alpha/Sub/leaf.data", bytes: 4096)
        try file("Home/Beta/b1.data", bytes: 4096); try file("Home/Beta/b2.data", bytes: 4096); try file("Home/Beta/b3.data", bytes: 4096)
        let sparse = try file("Home/Gamma/sparse.bin", bytes: 0)
        let handle = try FileHandle(forWritingTo: sparse); try handle.truncate(atOffset: 64 * 1024 * 1024); try handle.close()
        let home = root.appendingPathComponent("Home")
        let result = try DiskScanner.scan(root: home, home: home)
        let topDirs = result.nodes.filter { $0.parent == home.path && $0.path != home.path }
        XCTAssertEqual(RankingSort.files.sort(topDirs).first?.name, "Beta")
        XCTAssertEqual(RankingSort.logical.sort(topDirs).first?.name, "Gamma")
        let alpha = try XCTUnwrap(topDirs.first { $0.name == "Alpha" })
        XCTAssertTrue(HierarchyBrowser.canBrowse(alpha, in: result))
        let leaf = try XCTUnwrap(result.nodes.first { $0.name == "leaf.data" })
        XCTAssertFalse(HierarchyBrowser.canBrowse(leaf, in: result))
        let crumbs = HierarchyBrowser.breadcrumbs(root: home.path, current: home.appendingPathComponent("Alpha/Sub").path)
        XCTAssertEqual(crumbs.map(\.name), ["Home", "Alpha", "Sub"])
        XCTAssertEqual(FileCategory.classify("index.ts", allocated: 4096), .source)
        XCTAssertEqual(FileCategory.classify("stream.ts", allocated: 128 * 1024 * 1024), .video)
        XCTAssertTrue(RuleCatalog.protection(name: "stream.ts", directory: false).contains(.source))
        let recs = [
            Recommendation(node: .init(path: "/h/Library/Caches/AppA", allocated: 100), category: .browser),
            Recommendation(node: .init(path: "/h/project/.build", allocated: 200, protection: [.source]), category: .build)
        ]
        XCTAssertEqual(RecommendationQuery.rows(recs, filter: .eligible).map(\.node.name), ["AppA"])
        XCTAssertEqual(RecommendationQuery.rows(recs, filter: .protected).map(\.node.name), [".build"])
        XCTAssertEqual(RecommendationQuery.rows(recs, category: .build, query: "project").map(\.node.name), [".build"])
    }

    func testDeepComparisonSurfacesSubdirectoryChangesWithoutRedundantRemovedChildren() throws {
        let home = root.appendingPathComponent("Home")
        try file("Home/Workspace/ServiceA/data.bin", bytes: 8192)
        try file("Home/Legacy/Nested/old.bin", bytes: 8192)
        let before = try DiskScanner.scan(root: home, home: home)
        try file("Home/Workspace/ServiceA/data.bin", bytes: 32768)
        try FileManager.default.removeItem(at: home.appendingPathComponent("Legacy"))
        let after = try DiskScanner.scan(root: home, home: home)
        let deep = ScanComparison.changes(current: after, previous: before, depth: .deep)
        XCTAssertTrue(deep.contains { $0.0.name == "ServiceA" && $0.1 > 0 })
        XCTAssertTrue(deep.contains { $0.0.name == "Legacy" && $0.1 < 0 })
        XCTAssertFalse(deep.contains { $0.0.name == "Nested" })
    }

    func testStaleLargeFileFilterAndScanHistoryStore() throws {
        let recent = try file("recent.bin", bytes: 2 * 1024 * 1024)
        let stale = try file("stale.bin", bytes: 2 * 1024 * 1024)
        let oldDate = Date(timeIntervalSinceNow: -120 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: stale.path)
        let scan = try DiskScanner.scan(root: root)
        let large = scan.analysis?.largeFiles ?? []
        XCTAssertNotNil(large.first { $0.path == recent.path }?.modifiedAt)
        XCTAssertEqual(LargeFileQuery.rows(large, minimum: 1024 * 1024, staleDays: 0).count, 2)
        XCTAssertEqual(LargeFileQuery.rows(large, minimum: 1024 * 1024, staleDays: 90).map(\.name), ["stale.bin"])
        XCTAssertTrue(LargeFileQuery.rows(large, minimum: 1024 * 1024, staleDays: 365).isEmpty)

        var history: [ScanResult] = []
        for i in 0..<7 {
            var item = scan
            item.scannedAt = Date(timeIntervalSince1970: Double(1_700_000_000 + i * 60))
            history = ScanHistoryStore.append(item, into: history)
        }
        var partial = scan; partial.cancelled = true; partial.scannedAt = Date(timeIntervalSince1970: 1_800_000_000)
        history = ScanHistoryStore.append(partial, into: history)
        XCTAssertEqual(history.count, ScanHistoryStore.maxSnapshots)
        XCTAssertEqual(history.first?.scannedAt, Date(timeIntervalSince1970: Double(1_700_000_000 + 6 * 60)))
    }

}
