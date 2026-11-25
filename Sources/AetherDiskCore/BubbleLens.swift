import Foundation

public struct BubbleNode: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var path: String?
    public var cx: Double
    public var cy: Double
    public var radius: Double
    public var allocated: Int64
    public var fraction: Double
    public var colorIndex: Int
    public var isHub: Bool
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
        cx: Double,
        cy: Double,
        radius: Double,
        allocated: Int64,
        fraction: Double,
        colorIndex: Int,
        isHub: Bool = false,
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
        self.cx = cx
        self.cy = cy
        self.radius = radius
        self.allocated = allocated
        self.fraction = fraction
        self.colorIndex = colorIndex
        self.isHub = isHub
        self.isDirectory = isDirectory
        self.isProtected = isProtected
        self.isTailGroup = isTailGroup
        self.groupedCount = groupedCount
        self.fileCategory = fileCategory
        self.ageBucket = ageBucket
    }
}

public enum BubbleLensLayout {
    private struct RawItem {
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
        let rawRadius: Double
    }

    private struct PlacedCircle {
        let x: Double
        let y: Double
        let r: Double
    }

    /// CleanMyMac Space Lens style circle-packing layout in normalized [0, 1] x [0, 1] space.
    /// Guarantees:
    /// - Hub circle at (0.5, 0.5) when `nodes` has positive allocation
    /// - Pairwise non-overlapping circles (including hub)
    /// - All circles strictly within [0, 1] x [0, 1]
    /// - Area-proportional monotonic sizing with single-tiny-item no-merge rule
    public static func pack(
        nodes: [DiskNode],
        scopeTitle: String,
        scopePath: String,
        scopeAllocated: Int64? = nil,
        maxBubbles: Int = 18,
        minFraction: Double = 0.008
    ) -> [BubbleNode] {
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
        let sumAllocated = positive.reduce(Int64(0)) { $0 + $1.allocated }
        guard sumAllocated > 0, !positive.isEmpty else { return [] }

        let limit = max(1, maxBubbles)
        let maxPrimary = max(1, limit - 1)
        var primary: [DiskNode] = []
        var tail: [DiskNode] = []

        for (idx, node) in positive.enumerated() {
            let frac = Double(node.allocated) / Double(sumAllocated)
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

        let rMin = 0.34
        let rMax = 1.42
        var items: [RawItem] = []
        items.reserveCapacity(primary.count + (tail.isEmpty ? 0 : 1))

        for (idx, node) in primary.enumerated() {
            let frac = max(0.0, min(1.0, Double(node.allocated) / Double(sumAllocated)))
            let isDir = node.kind == .directory
            let rawR = rMin + (rMax - rMin) * sqrt(frac)
            items.append(
                RawItem(
                    id: node.path,
                    title: node.name,
                    path: node.path,
                    allocated: node.allocated,
                    fraction: frac,
                    colorIndex: idx,
                    isDirectory: isDir,
                    isProtected: !node.protection.isEmpty,
                    isTailGroup: false,
                    groupedCount: 1,
                    fileCategory: isDir ? .other : FileCategory.classify(node.name, allocated: node.allocated),
                    ageBucket: AgeBucket.classify(modifiedAt: node.modifiedAt),
                    rawRadius: rawR
                )
            )
        }

        if !tail.isEmpty {
            let tailAlloc = tail.reduce(Int64(0)) { $0 + $1.allocated }
            let frac = max(0.0, min(1.0, Double(tailAlloc) / Double(sumAllocated)))
            let rawR = rMin + (rMax - rMin) * sqrt(frac)
            items.append(
                RawItem(
                    id: "__tail__",
                    title: "其余 \(tail.count) 项",
                    path: nil,
                    allocated: tailAlloc,
                    fraction: frac,
                    colorIndex: primary.count,
                    isDirectory: false,
                    isProtected: tail.contains { !$0.protection.isEmpty },
                    isTailGroup: true,
                    groupedCount: tail.count,
                    fileCategory: .other,
                    ageBucket: AgeBucket.classify(modifiedAt: tail.compactMap(\.modifiedAt).max()),
                    rawRadius: rawR
                )
            )
        }

        let hubRawR = 1.05
        let gap = 0.10
        var placed: [PlacedCircle] = [PlacedCircle(x: 0.0, y: 0.0, r: hubRawR)]
        placed.reserveCapacity(items.count + 1)

        let goldenAngle = 2.399963229728653
        let candidateRayCount = 72

        for (idx, item) in items.enumerated() {
            let ri = item.rawRadius
            let baseAngle = Double(idx) * goldenAngle - Double.pi / 2.0
            var bestX = 0.0
            var bestY = -(hubRawR + ri + gap)
            var bestScore = Double.infinity

            for k in 0..<candidateRayCount {
                let theta = baseAngle + (2.0 * Double.pi * Double(k)) / Double(candidateRayCount)
                let cosT = cos(theta)
                let sinT = sin(theta)
                var requiredD = hubRawR + ri + gap

                for existing in placed {
                    let clearance = ri + existing.r + gap
                    let proj = existing.x * cosT + existing.y * sinT
                    let perp = -existing.x * sinT + existing.y * cosT
                    let absPerp = abs(perp)
                    if absPerp < clearance {
                        let candidateD = proj + sqrt(max(0.0, clearance * clearance - absPerp * absPerp))
                        if candidateD > requiredD {
                            requiredD = candidateD
                        }
                    }
                }

                // Slightly favor horizontal spread to fit wide stage viewports naturally while preserving strict circle distances.
                let px = requiredD * cosT
                let py = requiredD * sinT
                let visualScore = hypot(px * 0.94, py * 1.06) + Double(k) * 1e-6
                if visualScore < bestScore {
                    bestScore = visualScore
                    bestX = px
                    bestY = py
                }
            }

            placed.append(PlacedCircle(x: bestX, y: bestY, r: ri))
        }

        var maxExtent = hubRawR
        for circle in placed {
            let ext = hypot(circle.x, circle.y) + circle.r
            if ext > maxExtent { maxExtent = ext }
        }
        let scale = 0.468 / max(0.001, maxExtent)

        var output: [BubbleNode] = []
        output.reserveCapacity(items.count + 1)

        let effectiveScopeAllocated = max(sumAllocated, scopeAllocated ?? sumAllocated)
        output.append(
            BubbleNode(
                id: "__hub__:\(scopePath)",
                title: scopeTitle.isEmpty ? "/" : scopeTitle,
                path: scopePath,
                cx: 0.5,
                cy: 0.5,
                radius: hubRawR * scale,
                allocated: effectiveScopeAllocated,
                fraction: 1.0,
                colorIndex: 0,
                isHub: true,
                isDirectory: true,
                isProtected: false,
                isTailGroup: false,
                groupedCount: positive.count,
                fileCategory: .other,
                ageBucket: .recent30d
            )
        )

        for (i, item) in items.enumerated() {
            let c = placed[i + 1]
            output.append(
                BubbleNode(
                    id: item.id,
                    title: item.title,
                    path: item.path,
                    cx: 0.5 + c.x * scale,
                    cy: 0.5 + c.y * scale,
                    radius: c.r * scale,
                    allocated: item.allocated,
                    fraction: item.fraction,
                    colorIndex: item.colorIndex,
                    isHub: false,
                    isDirectory: item.isDirectory,
                    isProtected: item.isProtected,
                    isTailGroup: item.isTailGroup,
                    groupedCount: item.groupedCount,
                    fileCategory: item.fileCategory,
                    ageBucket: item.ageBucket
                )
            )
        }

        return output
    }

    public static func hitTest(bubbles: [BubbleNode], nx: Double, ny: Double) -> BubbleNode? {
        guard nx >= 0.0, nx <= 1.0, ny >= 0.0, ny <= 1.0 else { return nil }
        for bubble in bubbles.reversed() {
            if hypot(nx - bubble.cx, ny - bubble.cy) <= bubble.radius {
                return bubble
            }
        }
        return nil
    }
}
