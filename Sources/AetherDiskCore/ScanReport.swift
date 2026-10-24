import Foundation

public enum ScanReport {
    // Text columns are quoted and formula-escaped. Numbers are emitted from typed integer values only.
    static func cell(_ text: String) -> String {
        let leading = text.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = leading.map { "=+-@".contains($0) } == true ? "'" + text : text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    public static func csv(_ result: ScanResult, protectedPaths: [String] = []) -> String {
        let date = ISO8601DateFormatter().string(from: result.scannedAt)
        let status = result.cancelled ? "cancelled" : result.unreadable > 0 ? "partial" : "complete"
        var lines = ["section,path,name,kind,allocated_bytes,logical_bytes,files,protection,status,scanned_at"]
        func row(_ section: String, _ node: DiskNode) {
            let n = UserProtection.apply(node, paths: protectedPaths)
            let text = [section,n.path,n.name,n.kind.rawValue].map(cell).joined(separator: ",")
            lines.append(text + ",\(n.allocated),\(n.logical),\(n.fileCount)," + [n.protection.map(\.rawValue).sorted().joined(separator: "|"),status,date].map(cell).joined(separator: ","))
        }
        row("summary", .init(path: result.root, allocated: result.allocated, logical: result.logical, fileCount: result.files))
        for n in result.nodes { row("directory_sample", n) }
        for n in result.analysis?.largeFiles ?? [] { row("large_file", n) }
        for usage in result.analysis?.fileTypes ?? [] {
            row("file_type", .init(path: usage.category.rawValue, kind: .file, allocated: usage.allocated, logical: usage.logical, fileCount: usage.files))
        }
        for path in result.issues { row("unreadable", .init(path: path, restricted: true, protection: [.incomplete])) }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }
}
