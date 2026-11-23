import Foundation
import AppKit
import Quartz
import Darwin

/// 只读 Quick Look 预览控制器，仅向系统 QLPreviewPanel 提供标准化本地文件 URL。
@MainActor
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var currentURL: URL?

    private override init() {
        super.init()
    }

    func preview(path: String) {
        var st = stat()
        guard lstat(path, &st) == 0,
              (st.st_mode & S_IFMT) != S_IFLNK,
              FileManager.default.fileExists(atPath: path) else {
            return
        }

        let targetURL = URL(fileURLWithPath: path).standardizedFileURL
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(),
           panel.isVisible,
           currentURL?.standardizedFileURL.path == targetURL.path {
            panel.orderOut(nil)
            return
        }

        currentURL = targetURL
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            currentURL == nil ? 0 : 1
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)? {
        let url: URL? = MainActor.assumeIsolated {
            guard index == 0 else { return nil }
            return currentURL
        }
        return url as NSURL?
    }
}
