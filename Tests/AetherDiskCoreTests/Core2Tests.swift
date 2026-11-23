import XCTest
import Foundation
import Darwin
@testable import AetherDiskCore

final class Core2Tests: XCTestCase, @unchecked Sendable {
    var root: URL!
    private var restrictedPaths: [URL] = []

    override func setUpWithError() throws {
        restrictedPaths = []
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AetherDiskCore2-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for path in restrictedPaths.reversed() {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
        }
        restrictedPaths.removeAll()
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @discardableResult
    private func file(_ path: String, bytes: Int = 4096, byte: UInt8 = 7) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: byte, count: bytes).write(to: url)
        return url
    }

    @discardableResult
    private func makeSparseFile(_ path: String, logicalSize: UInt64) throws -> URL {
        let url = try file(path, bytes: 0)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: logicalSize)
        return url
    }

    private func duKiB(at url: URL, allowFailure: Bool) throws -> Int64 {
        let result = try SafetyInspector.runProcess("/usr/bin/du", ["-xsk", url.path], allowFailure: allowFailure)
        let firstToken = result.output.split(whereSeparator: \.isWhitespace).first
        return try XCTUnwrap(firstToken.flatMap { Int64($0) }, "du output missing KiB: \(result.output)")
    }

    private var home: URL { root.appendingPathComponent("Home") }

    private func sampleSunburstNodes() -> [DiskNode] {
        [
            DiskNode(path: "/scope/D1", kind: .directory, allocated: 5000),
            DiskNode(path: "/scope/D2", kind: .directory, allocated: 3000),
            DiskNode(path: "/scope/D3", kind: .directory, allocated: 1970),
            DiskNode(path: "/scope/tiny1.dat", kind: .file, allocated: 10),
            DiskNode(path: "/scope/tiny2.dat", kind: .file, allocated: 10),
            DiskNode(path: "/scope/tiny3.dat", kind: .file, allocated: 10),
            DiskNode(path: "/scope/D1/SubA", kind: .directory, allocated: 3500),
            DiskNode(path: "/scope/D1/SubB", kind: .directory, allocated: 1500),
            DiskNode(path: "/scope/D2/SubC", kind: .directory, allocated: 3000),
            DiskNode(path: "/scope/D1/SubA/Leaf1", kind: .directory, allocated: 2500),
            DiskNode(path: "/scope/D1/SubA/Leaf2", kind: .file, allocated: 1000),
            DiskNode(path: "/scope/D1/SubA/Leaf1/TooDeep.bin", kind: .file, allocated: 2500)
        ]
    }

    private func sampleBrowserNodes() -> [DiskNode] {
        [
            DiskNode(path: "/work/Projects", kind: .directory, allocated: 1800, logical: 1900, fileCount: 63),
            DiskNode(path: "/work/Media", kind: .directory, allocated: 900, logical: 900, fileCount: 4),
            DiskNode(path: "/work/Projects/AppA", kind: .directory, allocated: 500, logical: 1000, fileCount: 10),
            DiskNode(path: "/work/Projects/AppB", kind: .directory, allocated: 800, logical: 400, fileCount: 2),
            DiskNode(path: "/work/Projects/AppC", kind: .directory, allocated: 300, logical: 300, fileCount: 50),
            DiskNode(path: "/work/Projects/Secret", kind: .directory, allocated: 200, logical: 200, fileCount: 1),
            DiskNode(path: "/work/Projects/AppA/Build", kind: .directory, allocated: 300, logical: 600, fileCount: 5),
            DiskNode(path: "/work/Projects/AppA/Sources", kind: .directory, allocated: 200, logical: 400, fileCount: 5),
            DiskNode(path: "/work/Projects/AppA/Sources/main.swift", kind: .file, allocated: 200, logical: 400, fileCount: 1)
        ]
    }

    // MARK: - 1. 性能档位与并发扫描一致性

    func testPerformanceProfilesConfigurationAndCodableRoundTrip() throws {
        XCTAssertEqual(ScanPerformanceProfile.eco.maxConcurrency, 1)
        XCTAssertTrue(ScanPerformanceProfile.eco.throttleDiskIO)
        XCTAssertGreaterThanOrEqual(ScanPerformanceProfile.balanced.maxConcurrency, 2)
        XCTAssertLessThanOrEqual(ScanPerformanceProfile.balanced.maxConcurrency, 4)
        XCTAssertTrue(ScanPerformanceProfile.balanced.throttleDiskIO)
        XCTAssertGreaterThanOrEqual(ScanPerformanceProfile.fast.maxConcurrency, 2)
        XCTAssertLessThanOrEqual(ScanPerformanceProfile.fast.maxConcurrency, 6)
        XCTAssertFalse(ScanPerformanceProfile.fast.throttleDiskIO)

        for profile in ScanPerformanceProfile.allCases {
            XCTAssertEqual(profile.id, profile.rawValue)
            XCTAssertFalse(profile.title.isEmpty)
            XCTAssertFalse(profile.summary.isEmpty)
            let data = try JSONEncoder().encode(profile)
            XCTAssertEqual(try JSONDecoder().decode(ScanPerformanceProfile.self, from: data), profile)
        }
    }

    func testConcurrentScanConsistencyAcrossProfilesAndMatchesDu() throws {
        let outside = try file("Outside/secret.bin", bytes: 65_536)

        // >= 6 个子目录（含隐藏目录、跨目录/同目录硬链接、稀疏文件、长符号链接、0 权限受限目录）
        try file("Home/.hidden-cache/h1.bin", bytes: 8192)
        let hlOrigin = try file("Home/SubA/origin-a.bin", bytes: 16_384)
        try FileManager.default.linkItem(at: hlOrigin, to: home.appendingPathComponent("SubA/same-dir-link.bin"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent("SubB"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: hlOrigin, to: home.appendingPathComponent("SubB/cross-dir-link.bin"))

        let hlOrigin2 = try file("Home/SubC/origin-c.bin", bytes: 32_768)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("SubD"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: hlOrigin2, to: home.appendingPathComponent("SubD/cross-dir-link2.bin"))

        try makeSparseFile("Home/SubE/sparse.bin", logicalSize: 64 * 1024 * 1024)
        try file("Home/SubF/regular.bin", bytes: 12_288)

        try FileManager.default.createSymbolicLink(
            atPath: home.appendingPathComponent("SubB/long-symlink").path,
            withDestinationPath: String(repeating: "a/", count: 450)
        )
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("SubC/outside-link"),
            withDestinationURL: outside.deletingLastPathComponent()
        )

        let restrictedDir = try file("Home/Restricted/locked.bin", bytes: 8192).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: restrictedDir.path)
        restrictedPaths.append(restrictedDir)

        let eco = try DiskScanner.scan(root: home, home: home, profile: .eco)
        let balanced = try DiskScanner.scan(root: home, home: home, profile: .balanced)
        let fast = try DiskScanner.scan(root: home, home: home, profile: .fast)

        for other in [balanced, fast] {
            XCTAssertEqual(other.allocated, eco.allocated)
            XCTAssertEqual(other.logical, eco.logical)
            XCTAssertEqual(other.files, eco.files)
            XCTAssertEqual(other.directories, eco.directories)
            XCTAssertEqual(other.unreadable, eco.unreadable)
        }

        XCTAssertEqual(eco.files, 8)
        XCTAssertEqual(eco.unreadable, 1)
        XCTAssertFalse(eco.complete)
        XCTAssertEqual(eco.issues, [restrictedDir.path])
        let expectedLogical: Int64 = 8192 + 16_384 + 32_768 + (64 * 1024 * 1024) + 12_288
        XCTAssertEqual(eco.logical, expectedLogical)
        XCTAssertLessThan(eco.allocated, eco.logical)

        let kibWithRestricted = try duKiB(at: home, allowFailure: true)
        XCTAssertEqual((eco.allocated + 1023) / 1024, kibWithRestricted)

        // 恢复权限后验证完整可读目录树与 du -xsk (exit 0) 精确一致
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restrictedDir.path)
        restrictedPaths.removeAll()
        let fullEco = try DiskScanner.scan(root: home, home: home, profile: .eco)
        let fullBalanced = try DiskScanner.scan(root: home, home: home, profile: .balanced)
        let fullFast = try DiskScanner.scan(root: home, home: home, profile: .fast)
        XCTAssertTrue(fullEco.complete)
        XCTAssertEqual(fullEco.unreadable, 0)
        XCTAssertEqual(fullEco.files, 9)
        for other in [fullBalanced, fullFast] {
            XCTAssertEqual(other.allocated, fullEco.allocated)
            XCTAssertEqual(other.logical, fullEco.logical)
            XCTAssertEqual(other.files, fullEco.files)
            XCTAssertEqual(other.directories, fullEco.directories)
            XCTAssertEqual(other.unreadable, fullEco.unreadable)
        }
        let fullDuKiB = try duKiB(at: home, allowFailure: false)
        XCTAssertEqual((fullEco.allocated + 1023) / 1024, fullDuKiB)
    }

    // MARK: - 2. 纯元数据相似体积重复组 DuplicateSizeGroup

    func testDuplicateSizeGroupsDeduplicateHardlinksAcrossConcurrentSubdirs() throws {
        let miB = 1024 * 1024
        let size1 = miB + 200_000

        // 2 个独立 inode + 1 个跨子目录硬链接副本（不应算第 3 个），扩展名大小写不敏感
        let mp4A = try file("Home/Dir1/clipA.mp4", bytes: size1, byte: 1)
        let mp4B = try file("Home/Dir2/clipB.MP4", bytes: size1, byte: 2)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Dir3"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: mp4A, to: home.appendingPathComponent("Dir3/clipA-hardlink.mp4"))

        // 仅 1 个独立 inode + 1 个硬链接 -> 不可进入 duplicateGroups
        let soloISO = try file("Home/Dir4/onlyone.iso", bytes: miB + 50_000, byte: 3)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Dir5"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: soloISO, to: home.appendingPathComponent("Dir5/onlyone-link.iso"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Dir6"), withIntermediateDirectories: true)

        let result = try DiskScanner.scan(root: home, home: home, profile: .balanced)
        let groups = try XCTUnwrap(result.analysis?.duplicateGroups)
        XCTAssertEqual(groups.count, 1)

        let mp4Group = try XCTUnwrap(groups.first)
        XCTAssertEqual(mp4Group.id, "\(size1):mp4")
        XCTAssertEqual(mp4Group.logicalSize, Int64(size1))
        XCTAssertEqual(mp4Group.ext, "mp4")
        XCTAssertEqual(mp4Group.category, .video)
        XCTAssertEqual(mp4Group.files.count, 2)
        XCTAssertTrue(mp4Group.files.contains { $0.path == mp4B.path })
        let expectedTotal = mp4Group.files.reduce(Int64(0)) { $0 + $1.allocated }
        let expectedMax = mp4Group.files.map(\.allocated).max() ?? 0
        XCTAssertEqual(mp4Group.totalAllocated, expectedTotal)
        XCTAssertEqual(mp4Group.potentialRedundantAllocated, expectedTotal - expectedMax)
        XCTAssertGreaterThan(mp4Group.potentialRedundantAllocated, 0)

        let csv = ScanReport.csv(result)
        XCTAssertTrue(csv.contains("\"duplicate_suspect\""))
    }

    func testDuplicateSizeGroupsEnforce1MiBBoundaryExtensionMatchAndSparseRedundancy() throws {
        let miB = 1024 * 1024

        // 恰好 1 MiB 且无扩展名 -> "(无扩展名)"
        try file("Home/A/payloadOne", bytes: miB, byte: 1)
        try file("Home/B/payloadTwo", bytes: miB, byte: 2)

        // 普通文件 + 稀疏文件同逻辑体积与扩展名
        let denseImg = try file("Home/C/disk1.img", bytes: 2 * miB, byte: 3)
        let sparseImg = try makeSparseFile("Home/D/disk2.img", logicalSize: UInt64(2 * miB))

        // < 1 MiB 不归入
        try file("Home/A/small1.bin", bytes: miB - 1, byte: 4)
        try file("Home/B/small2.bin", bytes: miB - 1, byte: 4)

        // 同体积 >= 1 MiB 但不同扩展名不归入
        try file("Home/C/sameSize.dmg", bytes: miB + 300_000, byte: 5)
        try file("Home/D/sameSize.zip", bytes: miB + 300_000, byte: 6)

        let result = try DiskScanner.scan(root: home, home: home, profile: .eco)
        let groups = try XCTUnwrap(result.analysis?.duplicateGroups)
        XCTAssertEqual(groups.count, 2)

        let noExtGroup = try XCTUnwrap(groups.first { $0.ext == "(无扩展名)" })
        XCTAssertEqual(noExtGroup.logicalSize, Int64(miB))
        XCTAssertEqual(noExtGroup.files.count, 2)

        let imgGroup = try XCTUnwrap(groups.first { $0.ext == "img" })
        XCTAssertEqual(imgGroup.files.count, 2)
        let denseNode = try XCTUnwrap(imgGroup.files.first { $0.path == denseImg.path })
        let sparseNode = try XCTUnwrap(imgGroup.files.first { $0.path == sparseImg.path })
        XCTAssertEqual(imgGroup.totalAllocated, denseNode.allocated + sparseNode.allocated)
        XCTAssertEqual(imgGroup.potentialRedundantAllocated, imgGroup.totalAllocated - max(denseNode.allocated, sparseNode.allocated))

        XCTAssertFalse(groups.contains { $0.ext == "bin" || $0.ext == "dmg" || $0.ext == "zip" })

        // Codable round-trip
        let data = try JSONEncoder().encode(groups)
        XCTAssertEqual(try JSONDecoder().decode([DuplicateSizeGroup].self, from: data), groups)
    }

    // MARK: - 3. SunburstLayout

    func testSunburstLayoutRingAnglesContainmentAndMaxDepth() throws {
        XCTAssertTrue(SunburstLayout.build(nodes: [], scopePath: "/scope").isEmpty)
        XCTAssertTrue(SunburstLayout.build(nodes: sampleSunburstNodes(), scopePath: "/scope", maxDepth: 0).isEmpty)

        let arcs = SunburstLayout.build(nodes: sampleSunburstNodes(), scopePath: "/scope", maxDepth: 3, minAngle: 0.035, maxChildrenPerNode: 14)
        XCTAssertFalse(arcs.isEmpty)
        XCTAssertFalse(arcs.contains { $0.depth > 3 })

        let ring1 = arcs.filter { $0.depth == 1 }
        let ring1Span = ring1.reduce(0.0) { $0 + ($1.endAngle - $1.startAngle) }
        XCTAssertEqual(ring1Span, 2.0 * Double.pi, accuracy: 1e-12)

        let byPath = Dictionary(uniqueKeysWithValues: arcs.compactMap { arc in arc.path.map { ($0, arc) } })
        for arc in arcs where arc.depth > 1 {
            let parentPath = try XCTUnwrap(arc.parentPath)
            let parent = try XCTUnwrap(byPath[parentPath])
            XCTAssertGreaterThanOrEqual(arc.startAngle, parent.startAngle - 1e-12)
            XCTAssertLessThanOrEqual(arc.endAngle, parent.endAngle + 1e-12)
        }
    }

    func testSunburstLayoutTailMergingAndSingleItemNoMerge() throws {
        let arcs = SunburstLayout.build(nodes: sampleSunburstNodes(), scopePath: "/scope", maxDepth: 3, minAngle: 0.035, maxChildrenPerNode: 14)
        let tailArc = try XCTUnwrap(arcs.first { $0.depth == 1 && $0.isTailGroup })
        XCTAssertEqual(tailArc.groupedCount, 3)
        XCTAssertEqual(tailArc.allocated, 30)
        XCTAssertNil(tailArc.path)

        // 仅 1 个极小项时不得合并为“其余 1 项”
        let singleTinyNodes = [
            DiskNode(path: "/scope/Big", kind: .directory, allocated: 9990),
            DiskNode(path: "/scope/OnlyTiny.dat", kind: .file, allocated: 10)
        ]
        let singleTinyArcs = SunburstLayout.build(nodes: singleTinyNodes, scopePath: "/scope", maxDepth: 3, minAngle: 0.035)
        XCTAssertEqual(singleTinyArcs.count, 2)
        XCTAssertTrue(singleTinyArcs.allSatisfy { !$0.isTailGroup && $0.groupedCount == 1 })
    }

    func testSunburstLayoutHitTestCenterHoleAndAllRings() {
        let arcs = SunburstLayout.build(nodes: sampleSunburstNodes(), scopePath: "/scope", maxDepth: 3, minAngle: 0.035, maxChildrenPerNode: 14)
        let innerRadius = 60.0
        let ringWidth = 40.0

        XCTAssertNil(SunburstLayout.hitTest(arcs: arcs, dx: 0, dy: 0, innerRadius: innerRadius, ringWidth: ringWidth))
        XCTAssertNil(SunburstLayout.hitTest(arcs: arcs, dx: innerRadius - 1.0, dy: 0, innerRadius: innerRadius, ringWidth: ringWidth))
        XCTAssertNil(SunburstLayout.hitTest(arcs: arcs, dx: innerRadius + 3.5 * ringWidth, dy: 0, innerRadius: innerRadius, ringWidth: ringWidth))

        for arc in arcs {
            let midAngle = (arc.startAngle + arc.endAngle) / 2.0
            let midRadius = innerRadius + (Double(arc.depth) - 0.5) * ringWidth
            let hit = SunburstLayout.hitTest(
                arcs: arcs,
                dx: midRadius * cos(midAngle),
                dy: midRadius * sin(midAngle),
                innerRadius: innerRadius,
                ringWidth: ringWidth
            )
            XCTAssertEqual(hit?.id, arc.id)
        }
    }

    // MARK: - 4. TreemapLayout

    func testTreemapLayoutSquarifyBoundsNonOverlapAndArea() {
        XCTAssertTrue(TreemapLayout.squarify(nodes: []).isEmpty)

        var nodes: [DiskNode] = [
            DiskNode(path: "/t/Alpha", kind: .directory, allocated: 500_000),
            DiskNode(path: "/t/Beta", kind: .directory, allocated: 300_000),
            DiskNode(path: "/t/Gamma", kind: .directory, allocated: 120_000),
            DiskNode(path: "/t/Delta", kind: .file, allocated: 50_000),
            DiskNode(path: "/t/Epsilon", kind: .file, allocated: 25_000)
        ]
        for i in 1...5 {
            nodes.append(DiskNode(path: "/t/tiny\(i).bin", kind: .file, allocated: 1_000))
        }

        let rects = TreemapLayout.squarify(nodes: nodes, maxItems: 40, minFraction: 0.004)
        XCTAssertEqual(rects.count, 6)

        var totalArea = 0.0
        for rect in rects {
            XCTAssertGreaterThanOrEqual(rect.x, 0.0)
            XCTAssertGreaterThanOrEqual(rect.y, 0.0)
            XCTAssertGreaterThan(rect.width, 0.0)
            XCTAssertGreaterThan(rect.height, 0.0)
            XCTAssertLessThanOrEqual(rect.x + rect.width, 1.0001)
            XCTAssertLessThanOrEqual(rect.y + rect.height, 1.0001)
            totalArea += rect.width * rect.height
        }
        XCTAssertEqual(totalArea, 1.0, accuracy: 1e-4)

        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                let a = rects[i], b = rects[j]
                let overlapX = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
                let overlapY = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
                XCTAssertTrue(overlapX <= 1e-9 || overlapY <= 1e-9, "Overlapping rects: \(a.id) vs \(b.id)")
            }
        }
    }

    func testTreemapLayoutTailMergingAndHitTest() throws {
        var nodes: [DiskNode] = [
            DiskNode(path: "/t/Alpha", kind: .directory, allocated: 600_000),
            DiskNode(path: "/t/Beta", kind: .directory, allocated: 395_000)
        ]
        for i in 1...5 {
            nodes.append(DiskNode(path: "/t/tiny\(i).bin", kind: .file, allocated: 1_000))
        }

        let rects = TreemapLayout.squarify(nodes: nodes, maxItems: 40, minFraction: 0.004)
        let tail = try XCTUnwrap(rects.first { $0.isTailGroup })
        XCTAssertEqual(tail.groupedCount, 5)
        XCTAssertEqual(tail.allocated, 5_000)

        let singleTinyRects = TreemapLayout.squarify(
            nodes: [
                DiskNode(path: "/t/Huge", kind: .directory, allocated: 999_000),
                DiskNode(path: "/t/OneTiny", kind: .file, allocated: 1_000)
            ],
            maxItems: 40,
            minFraction: 0.004
        )
        XCTAssertEqual(singleTinyRects.count, 2)
        XCTAssertTrue(singleTinyRects.allSatisfy { !$0.isTailGroup })

        XCTAssertNil(TreemapLayout.hitTest(rects: rects, nx: -0.01, ny: 0.5))
        XCTAssertNil(TreemapLayout.hitTest(rects: rects, nx: 1.01, ny: 0.5))
        XCTAssertNil(TreemapLayout.hitTest(rects: rects, nx: 0.5, ny: -0.01))
        XCTAssertNil(TreemapLayout.hitTest(rects: rects, nx: 0.5, ny: 1.01))

        for rect in rects {
            let hit = TreemapLayout.hitTest(rects: rects, nx: rect.x + rect.width / 2.0, ny: rect.y + rect.height / 2.0)
            XCTAssertEqual(hit?.id, rect.id)
        }
    }

    // MARK: - 5. ColumnBrowserLayout

    func testColumnBrowserLayoutHierarchyDrilldownAndMaxColumns() {
        let nodes = sampleBrowserNodes()

        let cols = ColumnBrowserLayout.columns(
            root: "/work",
            activeScope: "/work/Projects",
            selectedPath: "/work/Projects/AppA",
            nodes: nodes
        )
        XCTAssertEqual(cols.map(\.path), ["/work", "/work/Projects", "/work/Projects/AppA"])
        XCTAssertEqual(cols[0].selectedChildPath, "/work/Projects")
        XCTAssertEqual(cols[1].selectedChildPath, "/work/Projects/AppA")
        XCTAssertNil(cols[2].selectedChildPath)
        XCTAssertEqual(cols[2].items.map(\.name), ["Build", "Sources"])

        // 选中文件不产生预览子列
        let colsLeafFile = ColumnBrowserLayout.columns(
            root: "/work",
            activeScope: "/work/Projects/AppA/Sources",
            selectedPath: "/work/Projects/AppA/Sources/main.swift",
            nodes: nodes
        )
        XCTAssertEqual(colsLeafFile.map(\.path), ["/work", "/work/Projects", "/work/Projects/AppA", "/work/Projects/AppA/Sources"])
        XCTAssertEqual(colsLeafFile.last?.selectedChildPath, "/work/Projects/AppA/Sources/main.swift")

        let colsLimited = ColumnBrowserLayout.columns(
            root: "/work",
            activeScope: "/work/Projects",
            selectedPath: "/work/Projects/AppA",
            nodes: nodes,
            maxColumns: 2
        )
        XCTAssertEqual(colsLimited.map(\.path), ["/work/Projects", "/work/Projects/AppA"])
    }

    func testColumnBrowserLayoutSortingAndUserProtectionPropagation() {
        let nodes = sampleBrowserNodes()

        let colsAllocated = ColumnBrowserLayout.columns(
            root: "/work",
            activeScope: "/work/Projects",
            selectedPath: "/work/Projects/AppA",
            nodes: nodes,
            sort: .allocated,
            protectedPaths: ["/work/Projects/Secret"]
        )
        XCTAssertEqual(colsAllocated[0].items.map(\.name), ["Projects", "Media"])
        XCTAssertTrue(colsAllocated[0].items[0].protection.contains(.user))
        XCTAssertFalse(colsAllocated[0].items[1].protection.contains(.user))

        XCTAssertEqual(colsAllocated[1].items.map(\.name), ["AppB", "AppA", "AppC", "Secret"])
        XCTAssertEqual(colsAllocated[1].items.first { $0.name == "Secret" }?.protection.contains(.user), true)
        XCTAssertEqual(colsAllocated[1].items.first { $0.name == "AppA" }?.protection.contains(.user), false)

        let colsLogical = ColumnBrowserLayout.columns(
            root: "/work",
            activeScope: "/work/Projects",
            selectedPath: "/work/Projects/AppA",
            nodes: nodes,
            sort: .logical
        )
        XCTAssertEqual(colsLogical[1].items.map(\.name), ["AppA", "AppB", "AppC", "Secret"])

        let colsFiles = ColumnBrowserLayout.columns(
            root: "/work",
            activeScope: "/work/Projects",
            selectedPath: "/work/Projects/AppA",
            nodes: nodes,
            sort: .files
        )
        XCTAssertEqual(colsFiles[1].items.map(\.name), ["AppC", "AppA", "AppB", "Secret"])
    }

    // MARK: - 6. VolumeSystem

    func testAPFSSnapshotInspectorParserFormats() {
        let standardOutput = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-11-23-091234.local
        com.apple.TimeMachine.2026-11-22-180000.local
        """
        let standard = APFSSnapshotInspector.parse(tmutilOutput: standardOutput)
        XCTAssertEqual(standard, [
            APFSSnapshotInfo(name: "com.apple.TimeMachine.2026-11-23-091234.local", dateLabel: "2026-11-23 09:12:34"),
            APFSSnapshotInfo(name: "com.apple.TimeMachine.2026-11-22-180000.local", dateLabel: "2026-11-22 18:00:00")
        ])

        XCTAssertTrue(APFSSnapshotInspector.parse(tmutilOutput: "").isEmpty)
        XCTAssertTrue(APFSSnapshotInspector.parse(tmutilOutput: "\n   \n\t\n").isEmpty)
        XCTAssertTrue(APFSSnapshotInspector.parse(tmutilOutput: "Snapshots for volume /System/Volumes/Data:\n").isEmpty)

        let nonStandardOutput = """
          Snapshots for /Volumes/Backup:
          com.apple.os.update-ABC123
          com.apple.os.update-ABC123
          custom-local-snapshot
        """
        XCTAssertEqual(APFSSnapshotInspector.parse(tmutilOutput: nonStandardOutput), [
            APFSSnapshotInfo(name: "com.apple.os.update-ABC123", dateLabel: "com.apple.os.update-ABC123"),
            APFSSnapshotInfo(name: "custom-local-snapshot", dateLabel: "custom-local-snapshot")
        ])
    }

    func testVolumeDiscoveryMountedVolumesAndDescriptorProperties() {
        let volumes = VolumeDiscovery.mountedVolumes()
        XCTAssertFalse(volumes.isEmpty)
        XCTAssertTrue(volumes.allSatisfy { $0.space.total > 0 && !$0.name.isEmpty && !$0.path.isEmpty })
        XCTAssertTrue(volumes.contains { $0.isSystemRoot && $0.path == "/" })

        let internalVol = VolumeDescriptor(name: "Mac", path: "/", space: VolumeSpace(total: 100, free: 50), fileSystemType: "APFS", isInternal: true, isRemovable: false, isReadOnly: false, isSystemRoot: true)
        let externalVol = VolumeDescriptor(name: "Backup", path: "/Volumes/Backup", space: VolumeSpace(total: 100, free: 50), fileSystemType: "APFS", isInternal: false, isRemovable: true, isReadOnly: false, isSystemRoot: false)
        XCTAssertFalse(internalVol.isExternal)
        XCTAssertTrue(externalVol.isExternal)
        XCTAssertNotEqual(internalVol, externalVol)
    }

    func testTrashInspectorReadOnlyInIsolatedTempHome() throws {
        // 仅使用测试临时目录下的虚拟 Home/.Trash，绝不读取或删除真实系统废纸篓
        XCTAssertEqual(TrashInspector.inspect(home: home), TrashSummary(itemCount: 0, allocated: 0, readable: true))

        let outside = try file("Outside/outside-trash.bin", bytes: 65_536)
        let trashItemA = try file("Home/.Trash/itemA.bin", bytes: 16_384)
        try file("Home/.Trash/Nested/itemB.bin", bytes: 8192)
        try FileManager.default.linkItem(at: trashItemA, to: home.appendingPathComponent(".Trash/Nested/itemA-hardlink.bin"))
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".Trash/sym-outside"), withDestinationURL: outside)

        let trashDir = home.appendingPathComponent(".Trash")
        let trashScan = try DiskScanner.scan(root: trashDir, home: home)
        var trashDirStat = stat()
        XCTAssertEqual(lstat(trashDir.path, &trashDirStat), 0)
        let expectedTrashAllocated = trashScan.allocated - Int64(trashDirStat.st_blocks) * 512

        let populatedSummary = TrashInspector.inspect(home: home)
        XCTAssertTrue(populatedSummary.readable)
        XCTAssertEqual(populatedSummary.itemCount, 3)
        XCTAssertEqual(populatedSummary.allocated, expectedTrashAllocated)

        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: trashDir.path)
        restrictedPaths.append(trashDir)
        XCTAssertEqual(TrashInspector.inspect(home: home), TrashSummary(itemCount: 0, allocated: 0, readable: false))
    }

    // MARK: - 7. 2.0 扩充缓存规则 & 1.0.2 旧格式 JSON 解码

    func testCore2BuildAndCompilerCacheRulesManifestEnforcement() throws {
        let zigCache = try file("Home/zig-app/.zig-cache/o.bin").deletingLastPathComponent()
        let zigOut = try file("Home/zig-app/zig-out/bin/app").deletingLastPathComponent().deletingLastPathComponent()
        let elixirBuild = try file("Home/elixir-app/_build/dev/app.beam").deletingLastPathComponent().deletingLastPathComponent()
        let cmakeDebug = try file("Home/cmake-app/cmake-build-debug/app.o").deletingLastPathComponent()
        let cmakeRelease = try file("Home/cmake-app/cmake-build-release/app.o").deletingLastPathComponent()
        let rspackCache = try file("Home/rspack-app/.rspack_cache/chunk.bin").deletingLastPathComponent()

        XCTAssertNil(RuleCatalog.category(for: zigCache, home: home))
        XCTAssertNil(RuleCatalog.category(for: zigOut, home: home))
        XCTAssertNil(RuleCatalog.category(for: elixirBuild, home: home))
        XCTAssertNil(RuleCatalog.category(for: cmakeDebug, home: home))
        XCTAssertNil(RuleCatalog.category(for: cmakeRelease, home: home))
        XCTAssertNil(RuleCatalog.category(for: rspackCache, home: home))

        // 清单为目录或符号链接时必须拒绝
        let zigManifest = home.appendingPathComponent("zig-app/build.zig")
        try FileManager.default.createDirectory(at: zigManifest, withIntermediateDirectories: true)
        XCTAssertNil(RuleCatalog.category(for: zigCache, home: home))
        try FileManager.default.removeItem(at: zigManifest)

        let outsideManifest = try file("Outside/build.zig", bytes: 32)
        try FileManager.default.createSymbolicLink(at: zigManifest, withDestinationURL: outsideManifest)
        XCTAssertNil(RuleCatalog.category(for: zigCache, home: home))
        try FileManager.default.removeItem(at: zigManifest)

        // 创建合法常规清单文件后识别为 .build
        try file("Home/zig-app/build.zig", bytes: 64)
        try file("Home/elixir-app/mix.exs", bytes: 64)
        try file("Home/cmake-app/CMakeLists.txt", bytes: 64)
        try file("Home/rspack-app/package.json", bytes: 64)

        XCTAssertEqual(RuleCatalog.category(for: zigCache, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: zigOut, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: elixirBuild, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: cmakeDebug, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: cmakeRelease, home: home), .build)
        XCTAssertEqual(RuleCatalog.category(for: rspackCache, home: home), .build)

        XCTAssertEqual(RuleCatalog.projectMarkers(in: ["README.md", "build.zig", "mix.exs"]), ["build.zig", "mix.exs"])
        XCTAssertTrue(RuleCatalog.protection(name: "build.zig", directory: false).contains(.source))
        XCTAssertTrue(RuleCatalog.protection(name: "main.zig", directory: false).contains(.source))

        for rel in [
            "Home/.cache/torch",
            "Home/.cache/ms-playwright",
            "Home/.cache/puppeteer",
            "Home/.cache/pre-commit",
            "Home/.cache/bazel",
            "Home/.cache/electron",
            "Home/.cache/cypress"
        ] {
            let dir = try file("\(rel)/blob.data").deletingLastPathComponent()
            XCTAssertEqual(RuleCatalog.category(for: dir, home: home), .compiler, rel)
        }
        XCTAssertNoThrow(try SafetyInspector.inspect(home.appendingPathComponent(".cache/torch"), home: home))
    }

    func testLegacy102SnapshotJSONDecodesLosslesslyWithoutDuplicateGroups() throws {
        try file("Home/Sample/a.mp4", bytes: 2 * 1024 * 1024)
        try file("Home/Sample/b.mp4", bytes: 2 * 1024 * 1024)
        let current = try DiskScanner.scan(root: home.appendingPathComponent("Sample"), home: home)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(current)
        var rawObj = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var analysisObj = try XCTUnwrap(rawObj["analysis"] as? [String: Any])
        analysisObj.removeValue(forKey: "duplicateGroups")
        rawObj["analysis"] = analysisObj
        let legacy102Data = try JSONSerialization.data(withJSONObject: rawObj)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScanResult.self, from: legacy102Data)
        XCTAssertEqual(decoded.root, current.root)
        XCTAssertEqual(decoded.allocated, current.allocated)
        XCTAssertEqual(decoded.logical, current.logical)
        XCTAssertEqual(decoded.files, current.files)
        XCTAssertEqual(decoded.directories, current.directories)
        XCTAssertEqual(decoded.nodes, current.nodes)
        XCTAssertEqual(decoded.analysis?.fileTypes.count, current.analysis?.fileTypes.count)
        XCTAssertEqual(decoded.analysis?.largeFiles, current.analysis?.largeFiles)
        XCTAssertEqual(decoded.analysis?.projects, current.analysis?.projects)
        XCTAssertEqual(decoded.analysis?.ageBuckets, current.analysis?.ageBuckets)
        XCTAssertEqual(decoded.analysis?.duplicateGroups, [])
    }

    // MARK: - 8. CLI 2.0 参数解析

    func testCLI2OptionsParsingAndRejectionOfInvalidFlags() throws {
        let userHome = FileManager.default.homeDirectoryForCurrentUser.path

        let versionOnly = try ScanCLIOptions.parse(["--version"])
        XCTAssertTrue(versionOnly.showVersion)
        XCTAssertEqual(versionOnly.rootPath, "")

        let volumesOnly = try ScanCLIOptions.parse(["--volumes"])
        XCTAssertTrue(volumesOnly.showVolumes)
        XCTAssertEqual(volumesOnly.rootPath, "")

        let full = try ScanCLIOptions.parse(["~/Downloads", "--profile", "eco", "--duplicates", "--volumes", "--top", "25"])
        XCTAssertEqual(full.rootPath, userHome + "/Downloads")
        XCTAssertEqual(full.profile, .eco)
        XCTAssertTrue(full.showDuplicates)
        XCTAssertTrue(full.showVolumes)
        XCTAssertEqual(full.topLimit, 25)

        XCTAssertEqual(try ScanCLIOptions.parse(["/tmp", "--profile", "balanced"]).profile, .balanced)
        XCTAssertEqual(try ScanCLIOptions.parse(["/tmp", "--profile", "fast"]).profile, .fast)

        XCTAssertThrowsError(try ScanCLIOptions.parse([]))
        XCTAssertThrowsError(try ScanCLIOptions.parse(["/tmp", "--profile", "turbo"]))
        XCTAssertThrowsError(try ScanCLIOptions.parse(["/tmp", "--profile"]))
        XCTAssertThrowsError(try ScanCLIOptions.parse(["--duplicates"]))
        XCTAssertThrowsError(try ScanCLIOptions.parse(["/tmp", "--bogus-flag"]))
        XCTAssertThrowsError(try ScanCLIOptions.parse(["/tmp", "/var"]))
    }
}
