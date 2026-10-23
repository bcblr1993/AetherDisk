import Foundation
public enum ScanComparison {
    public static func changes(current: ScanResult, previous: ScanResult) -> [(DiskNode, Int64)] {
        guard current.root == previous.root else { return [] }
        let new = Dictionary(uniqueKeysWithValues: current.nodes.filter { $0.parent == current.root && $0.path != current.root }.map { ($0.path, $0) })
        let old = Dictionary(uniqueKeysWithValues: previous.nodes.filter { $0.parent == previous.root && $0.path != previous.root }.map { ($0.path, $0) })
        return Set(new.keys).union(old.keys).map { path in
            var node = new[path] ?? old[path]!
            if new[path] == nil { node.allocated = 0; node.logical = 0; node.fileCount = 0 }
            return (node, (new[path]?.allocated ?? 0) - (old[path]?.allocated ?? 0))
        }.sorted { abs($0.1) > abs($1.1) }
    }
}
