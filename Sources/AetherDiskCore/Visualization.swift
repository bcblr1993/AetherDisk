import Foundation

public enum VisualizationColorMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case hierarchy, fileType, age, protection

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hierarchy: "按目录"
        case .fileType: "按类型"
        case .age: "按陈旧度"
        case .protection: "按保护"
        }
    }
}

public struct SunburstArc: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var path: String?
    public var parentPath: String?
    public var depth: Int
    public var startAngle: Double
    public var endAngle: Double
    public var allocated: Int64
    public var fraction: Double
    public var colorIndex: Int
    public var isDirectory: Bool
    public var isProtected: Bool
    public var isTailGroup: Bool
    public var groupedCount: Int
    public var fileCategory: FileCategory
    public var ageBucket: AgeBucket

    public init(
        id: String,
        title: String,
        path: String?,
        parentPath: String?,
        depth: Int,
        startAngle: Double,
        endAngle: Double,
        allocated: Int64,
        fraction: Double,
        colorIndex: Int,
        isDirectory: Bool,
        isProtected: Bool,
        isTailGroup: Bool,
        groupedCount: Int,
        fileCategory: FileCategory,
        ageBucket: AgeBucket
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.parentPath = parentPath
        self.depth = depth
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.allocated = allocated
        self.fraction = fraction
        self.colorIndex = colorIndex
        self.isDirectory = isDirectory
        self.isProtected = isProtected
        self.isTailGroup = isTailGroup
        self.groupedCount = groupedCount
        self.fileCategory = fileCategory
        self.ageBucket = ageBucket
    }
}

public enum SunburstLayout {
    private static let fullCircle = 2.0 * Double.pi

    public static func build(
        nodes: [DiskNode],
        scopePath: String,
        maxDepth: Int = 3,
        minAngle: Double = 0.035,
        maxChildrenPerNode: Int = 14
    ) -> [SunburstArc] {
        guard maxDepth >= 1 else { return [] }
        let stdScope = URL(fileURLWithPath: scopePath).standardizedFileURL.path
        var uniqueByPath: [String: DiskNode] = [:]
        uniqueByPath.reserveCapacity(nodes.count)
        for node in nodes where node.allocated > 0 {
            if let existing = uniqueByPath[node.path] {
                if node.allocated > existing.allocated {
                    uniqueByPath[node.path] = node
                }
            } else {
                uniqueByPath[node.path] = node
            }
        }

        var childrenByParent: [String: [DiskNode]] = [:]
        for node in uniqueByPath.values where node.path != node.parent {
            childrenByParent[node.parent, default: []].append(node)
        }
        for key in childrenByParent.keys {
            childrenByParent[key]?.sort {
                $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated
            }
        }

        guard let topChildren = childrenByParent[stdScope], !topChildren.isEmpty else { return [] }
        let totalScopeAllocated = topChildren.reduce(Int64(0)) { $0 + $1.allocated }
        guard totalScopeAllocated > 0 else { return [] }

        var arcs: [SunburstArc] = []
        let limit = max(1, maxChildrenPerNode)

        func layoutRing(
            parentPath: String,
            children: [DiskNode],
            depth: Int,
            startAngle: Double,
            endAngle: Double,
            inheritedColorIndex: Int?
        ) {
            let span = endAngle - startAngle
            guard span > 0 else { return }
            let childrenTotal = children.reduce(Int64(0)) { $0 + $1.allocated }
            guard childrenTotal > 0 else { return }

            var primary: [DiskNode] = []
            var tail: [DiskNode] = []
            let maxPrimary = max(1, limit - 1)
            for (idx, child) in children.enumerated() {
                let childAngle = span * (Double(child.allocated) / Double(childrenTotal))
                if primary.isEmpty || (idx < maxPrimary && childAngle >= minAngle) {
                    primary.append(child)
                } else {
                    tail.append(child)
                }
            }
            if tail.count == 1, let single = tail.first {
                primary.append(single)
                tail.removeAll()
            }

            enum Slice {
                case single(DiskNode, Int)
                case tail([DiskNode], Int)
            }

            var slices: [Slice] = []
            for (idx, node) in primary.enumerated() {
                let colorIdx = inheritedColorIndex ?? idx
                slices.append(.single(node, colorIdx))
            }
            if !tail.isEmpty {
                let colorIdx = inheritedColorIndex ?? primary.count
                slices.append(.tail(tail, colorIdx))
            }

            var cursor = startAngle
            for (idx, slice) in slices.enumerated() {
                let isLast = idx == slices.count - 1
                switch slice {
                case .single(let node, let colorIdx):
                    let rawEnd = cursor + span * (Double(node.allocated) / Double(childrenTotal))
                    let arcEnd = isLast ? endAngle : min(endAngle, rawEnd)
                    let isDir = node.kind == .directory
                    let category: FileCategory = isDir ? .other : FileCategory.classify(node.name, allocated: node.allocated)
                    let age = AgeBucket.classify(modifiedAt: node.modifiedAt)
                    let arc = SunburstArc(
                        id: node.path,
                        title: node.name,
                        path: node.path,
                        parentPath: parentPath,
                        depth: depth,
                        startAngle: cursor,
                        endAngle: arcEnd,
                        allocated: node.allocated,
                        fraction: Double(node.allocated) / Double(totalScopeAllocated),
                        colorIndex: colorIdx,
                        isDirectory: isDir,
                        isProtected: !node.protection.isEmpty,
                        isTailGroup: false,
                        groupedCount: 1,
                        fileCategory: category,
                        ageBucket: age
                    )
                    arcs.append(arc)
                    if isDir && depth < maxDepth, let subChildren = childrenByParent[node.path], !subChildren.isEmpty {
                        layoutRing(
                            parentPath: node.path,
                            children: subChildren,
                            depth: depth + 1,
                            startAngle: cursor,
                            endAngle: arcEnd,
                            inheritedColorIndex: colorIdx
                        )
                    }
                    cursor = arcEnd

                case .tail(let grouped, let colorIdx):
                    let tailAllocated = grouped.reduce(Int64(0)) { $0 + $1.allocated }
                    let rawEnd = cursor + span * (Double(tailAllocated) / Double(childrenTotal))
                    let arcEnd = isLast ? endAngle : min(endAngle, rawEnd)
                    let anyProtected = grouped.contains { !$0.protection.isEmpty }
                    let newestModified = grouped.compactMap(\.modifiedAt).max()
                    let arc = SunburstArc(
                        id: "\(parentPath)/__tail__/\(depth)",
                        title: "其余 \(grouped.count) 项",
                        path: nil,
                        parentPath: parentPath,
                        depth: depth,
                        startAngle: cursor,
                        endAngle: arcEnd,
                        allocated: tailAllocated,
                        fraction: Double(tailAllocated) / Double(totalScopeAllocated),
                        colorIndex: colorIdx,
                        isDirectory: false,
                        isProtected: anyProtected,
                        isTailGroup: true,
                        groupedCount: grouped.count,
                        fileCategory: .other,
                        ageBucket: AgeBucket.classify(modifiedAt: newestModified)
                    )
                    arcs.append(arc)
                    cursor = arcEnd
                }
            }
        }

        layoutRing(
            parentPath: stdScope,
            children: topChildren,
            depth: 1,
            startAngle: 0,
            endAngle: fullCircle,
            inheritedColorIndex: nil
        )

        return arcs.sorted {
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            if $0.startAngle != $1.startAngle { return $0.startAngle < $1.startAngle }
            return $0.id < $1.id
        }
    }

    public static func hitTest(
        arcs: [SunburstArc],
        dx: Double,
        dy: Double,
        innerRadius: Double,
        ringWidth: Double
    ) -> SunburstArc? {
        let r = hypot(dx, dy)
        guard r >= innerRadius else { return nil }
        let ring = Int(floor((r - innerRadius) / max(1.0, ringWidth))) + 1
        var angle = atan2(dy, dx)
        if angle < 0 { angle += fullCircle }
        return arcs.first { arc in
            arc.depth == ring && angle >= arc.startAngle && angle <= arc.endAngle
        }
    }
}

public struct TreemapRect: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var path: String?
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var allocated: Int64
    public var fraction: Double
    public var colorIndex: Int
    public var isDirectory: Bool
    public var isProtected: Bool
    public var isTailGroup: Bool
    public var groupedCount: Int
    public var fileCategory: FileCategory
    public var ageBucket: AgeBucket

    public init(
        id: String,
        title: String,
        path: String?,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        allocated: Int64,
        fraction: Double,
        colorIndex: Int,
        isDirectory: Bool,
        isProtected: Bool,
        isTailGroup: Bool,
        groupedCount: Int,
        fileCategory: FileCategory,
        ageBucket: AgeBucket
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.allocated = allocated
        self.fraction = fraction
        self.colorIndex = colorIndex
        self.isDirectory = isDirectory
        self.isProtected = isProtected
        self.isTailGroup = isTailGroup
        self.groupedCount = groupedCount
        self.fileCategory = fileCategory
        self.ageBucket = ageBucket
    }
}

public enum TreemapLayout {
    private struct Item {
        let id: String
        let title: String
        let path: String?
        let allocated: Int64
        let fraction: Double
        let colorIndex: Int
        let isDirectory: Bool
        let isProtected: Bool
        let isTailGroup: Bool
        let groupedCount: Int
        let fileCategory: FileCategory
        let ageBucket: AgeBucket
    }

    public static func squarify(
        nodes: [DiskNode],
        maxItems: Int = 40,
        minFraction: Double = 0.004
    ) -> [TreemapRect] {
        var uniqueByPath: [String: DiskNode] = [:]
        uniqueByPath.reserveCapacity(nodes.count)
        for node in nodes where node.allocated > 0 {
            if let existing = uniqueByPath[node.path] {
                if node.allocated > existing.allocated {
                    uniqueByPath[node.path] = node
                }
            } else {
                uniqueByPath[node.path] = node
            }
        }

        let positive = uniqueByPath.values.sorted {
            $0.allocated == $1.allocated ? $0.path < $1.path : $0.allocated > $1.allocated
        }
        let total = positive.reduce(Int64(0)) { $0 + $1.allocated }
        guard total > 0, !positive.isEmpty else { return [] }

        let limit = max(1, maxItems)
        let maxPrimary = max(1, limit - 1)
        var primary: [DiskNode] = []
        var tail: [DiskNode] = []

        for (idx, node) in positive.enumerated() {
            let frac = Double(node.allocated) / Double(total)
            if primary.isEmpty || (idx < maxPrimary && frac >= minFraction) {
                primary.append(node)
            } else {
                tail.append(node)
            }
        }
        if tail.count == 1, let single = tail.first {
            primary.append(single)
            tail.removeAll()
        }

        var items: [Item] = []
        items.reserveCapacity(primary.count + (tail.isEmpty ? 0 : 1))
        for (idx, node) in primary.enumerated() {
            let isDir = node.kind == .directory
            items.append(
                Item(
                    id: node.path,
                    title: node.name,
                    path: node.path,
                    allocated: node.allocated,
                    fraction: Double(node.allocated) / Double(total),
                    colorIndex: idx,
                    isDirectory: isDir,
                    isProtected: !node.protection.isEmpty,
                    isTailGroup: false,
                    groupedCount: 1,
                    fileCategory: isDir ? .other : FileCategory.classify(node.name, allocated: node.allocated),
                    ageBucket: AgeBucket.classify(modifiedAt: node.modifiedAt)
                )
            )
        }
        if !tail.isEmpty {
            let tailAllocated = tail.reduce(Int64(0)) { $0 + $1.allocated }
            items.append(
                Item(
                    id: "__tail__",
                    title: "其余 \(tail.count) 项",
                    path: nil,
                    allocated: tailAllocated,
                    fraction: Double(tailAllocated) / Double(total),
                    colorIndex: primary.count,
                    isDirectory: false,
                    isProtected: tail.contains { !$0.protection.isEmpty },
                    isTailGroup: true,
                    groupedCount: tail.count,
                    fileCategory: .other,
                    ageBucket: AgeBucket.classify(modifiedAt: tail.compactMap(\.modifiedAt).max())
                )
            )
        }

        // Keep areas sorted descending (e.g. if tail group exceeds the smallest primary item).
        items.sort {
            if $0.fraction != $1.fraction { return $0.fraction > $1.fraction }
            return $0.id < $1.id
        }

        var rects: [TreemapRect] = []
        rects.reserveCapacity(items.count)

        var rx = 0.0
        var ry = 0.0
        var rw = 1.0
        var rh = 1.0

        func worst(_ row: [Item], side: Double, scale: Double) -> Double {
            guard !row.isEmpty, side > 0, scale > 0 else { return .infinity }
            let s = row.reduce(0.0) { $0 + $1.fraction * scale }
            let maxArea = row.map { $0.fraction * scale }.max() ?? 0
            let minArea = row.map { $0.fraction * scale }.min() ?? 0
            guard s > 0, minArea > 0 else { return .infinity }
            let w2 = side * side
            let s2 = s * s
            return max((w2 * maxArea) / s2, s2 / (w2 * minArea))
        }

        func commitRow(_ row: [Item], remainingSumAfterRow: Double) {
            guard !row.isEmpty else { return }
            let rowSum = row.reduce(0.0) { $0 + $1.fraction }
            let totalRemaining = rowSum + remainingSumAfterRow
            let isLastRow = remainingSumAfterRow <= 0
            let ratio = (totalRemaining > 0 && !isLastRow) ? min(1.0, max(0.0, rowSum / totalRemaining)) : 1.0

            if rw >= rh {
                let stripW = isLastRow ? rw : rw * ratio
                var cy = ry
                for (j, item) in row.enumerated() {
                    let h = (j == row.count - 1) ? max(0.0, ry + rh - cy) : (rowSum > 0 ? rh * (item.fraction / rowSum) : 0.0)
                    rects.append(
                        TreemapRect(
                            id: item.id,
                            title: item.title,
                            path: item.path,
                            x: rx,
                            y: cy,
                            width: stripW,
                            height: h,
                            allocated: item.allocated,
                            fraction: item.fraction,
                            colorIndex: item.colorIndex,
                            isDirectory: item.isDirectory,
                            isProtected: item.isProtected,
                            isTailGroup: item.isTailGroup,
                            groupedCount: item.groupedCount,
                            fileCategory: item.fileCategory,
                            ageBucket: item.ageBucket
                        )
                    )
                    cy += h
                }
                rx += stripW
                rw = max(0.0, rw - stripW)
            } else {
                let stripH = isLastRow ? rh : rh * ratio
                var cx = rx
                for (j, item) in row.enumerated() {
                    let w = (j == row.count - 1) ? max(0.0, rx + rw - cx) : (rowSum > 0 ? rw * (item.fraction / rowSum) : 0.0)
                    rects.append(
                        TreemapRect(
                            id: item.id,
                            title: item.title,
                            path: item.path,
                            x: cx,
                            y: ry,
                            width: w,
                            height: stripH,
                            allocated: item.allocated,
                            fraction: item.fraction,
                            colorIndex: item.colorIndex,
                            isDirectory: item.isDirectory,
                            isProtected: item.isProtected,
                            isTailGroup: item.isTailGroup,
                            groupedCount: item.groupedCount,
                            fileCategory: item.fileCategory,
                            ageBucket: item.ageBucket
                        )
                    )
                    cx += w
                }
                ry += stripH
                rh = max(0.0, rh - stripH)
            }
        }

        var row: [Item] = []
        var idx = 0
        var totalRemainingFraction = items.reduce(0.0) { $0 + $1.fraction }

        while idx < items.count {
            let side = min(rw, rh)
            let boxArea = rw * rh
            let scale = totalRemainingFraction > 0 ? (boxArea / totalRemainingFraction) : 1.0
            let nextItem = items[idx]
            if row.isEmpty {
                row.append(nextItem)
                idx += 1
            } else {
                let currentWorst = worst(row, side: side, scale: scale)
                let candidateWorst = worst(row + [nextItem], side: side, scale: scale)
                if candidateWorst <= currentWorst {
                    row.append(nextItem)
                    idx += 1
                } else {
                    let rowSum = row.reduce(0.0) { $0 + $1.fraction }
                    totalRemainingFraction = max(0.0, totalRemainingFraction - rowSum)
                    commitRow(row, remainingSumAfterRow: items[idx...].reduce(0.0) { $0 + $1.fraction })
                    row.removeAll(keepingCapacity: true)
                }
            }
        }
        if !row.isEmpty {
            commitRow(row, remainingSumAfterRow: 0.0)
        }

        return rects
    }

    public static func hitTest(rects: [TreemapRect], nx: Double, ny: Double) -> TreemapRect? {
        guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { return nil }
        return rects.first { rect in
            nx >= rect.x && nx <= rect.x + rect.width && ny >= rect.y && ny <= rect.y + rect.height
        }
    }
}

public struct MillerColumn: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public var path: String
    public var title: String
    public var totalAllocated: Int64
    public var items: [DiskNode]
    public var selectedChildPath: String?

    public init(
        path: String,
        title: String,
        totalAllocated: Int64,
        items: [DiskNode],
        selectedChildPath: String? = nil
    ) {
        self.path = path
        self.title = title
        self.totalAllocated = totalAllocated
        self.items = items
        self.selectedChildPath = selectedChildPath
    }
}

public enum ColumnBrowserLayout {
    public static func columns(
        root: String,
        activeScope: String,
        selectedPath: String?,
        nodes: [DiskNode],
        sort: RankingSort = .allocated,
        protectedPaths: [String] = [],
        maxColumns: Int = 4
    ) -> [MillerColumn] {
        guard maxColumns > 0 else { return [] }
        let stdRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        let stdScope = URL(fileURLWithPath: activeScope).standardizedFileURL.path
        let stdSelected = selectedPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

        var nodeByPath: [String: DiskNode] = [:]
        nodeByPath.reserveCapacity(nodes.count)
        for node in nodes {
            if let existing = nodeByPath[node.path] {
                if node.allocated > existing.allocated {
                    nodeByPath[node.path] = node
                }
            } else {
                nodeByPath[node.path] = node
            }
        }

        var childrenByParent: [String: [DiskNode]] = [:]
        for node in nodeByPath.values where node.path != node.parent {
            childrenByParent[node.parent, default: []].append(node)
        }

        var chain: [String] = []
        let scopePrefix = stdRoot == "/" ? "/" : stdRoot + "/"
        if stdScope == stdRoot || stdScope.hasPrefix(scopePrefix) {
            var cursor = stdScope
            while true {
                chain.append(cursor)
                if cursor == stdRoot || cursor == "/" { break }
                cursor = URL(fileURLWithPath: cursor).deletingLastPathComponent().path
            }
            chain.reverse()
        } else {
            chain = [stdRoot]
        }

        let effectiveScope = chain.last ?? stdRoot
        var extraColumns: [String] = []
        var activeSelectedChild: String? = nil
        if let stdSelected {
            let selectedParent = URL(fileURLWithPath: stdSelected).deletingLastPathComponent().path
            if selectedParent == effectiveScope {
                activeSelectedChild = stdSelected
                let isDir = nodeByPath[stdSelected]?.kind != .file
                if isDir, let previewItems = childrenByParent[stdSelected], !previewItems.isEmpty {
                    extraColumns = [stdSelected]
                }
            } else {
                let effectivePrefix = effectiveScope == "/" ? "/" : effectiveScope + "/"
                if stdSelected.hasPrefix(effectivePrefix),
                   nodeByPath[stdSelected]?.kind != .file,
                   let previewItems = childrenByParent[stdSelected],
                   !previewItems.isEmpty {
                    var cursor = stdSelected
                    var subChain: [String] = []
                    while cursor != effectiveScope && cursor != "/" {
                        subChain.append(cursor)
                        cursor = URL(fileURLWithPath: cursor).deletingLastPathComponent().path
                    }
                    extraColumns = subChain.reversed()
                }
            }
        }

        chain.append(contentsOf: extraColumns)

        var result: [MillerColumn] = []
        result.reserveCapacity(chain.count)

        for (idx, colPath) in chain.enumerated() {
            let rawItems = childrenByParent[colPath] ?? []
            let protectedItems = rawItems.map { UserProtection.apply($0, paths: protectedPaths) }
            let sortedItems = sort.sort(protectedItems)
            let itemsSum = sortedItems.reduce(Int64(0)) { $0 + $1.allocated }
            let colTotal: Int64
            if let colNode = nodeByPath[colPath], colNode.allocated > 0 {
                colTotal = colNode.allocated
            } else {
                colTotal = itemsSum
            }

            let selectedChild: String?
            if idx + 1 < chain.count {
                selectedChild = chain[idx + 1]
            } else if colPath == effectiveScope {
                selectedChild = activeSelectedChild
            } else {
                selectedChild = nil
            }

            let title = colPath == "/" ? "/" : URL(fileURLWithPath: colPath).lastPathComponent
            result.append(
                MillerColumn(
                    path: colPath,
                    title: title,
                    totalAllocated: colTotal,
                    items: sortedItems,
                    selectedChildPath: selectedChild
                )
            )
        }

        if result.count > maxColumns {
            return Array(result.suffix(maxColumns))
        }
        return result
    }
}
