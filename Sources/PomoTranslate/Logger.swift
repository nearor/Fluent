import Foundation

/// 简单的文件日志，用于诊断（写到 app 旁边的 pomo.log）。
/// 自用调试用，定位问题后可移除。
enum Log {
    private static let url: URL = {
        // 写到用户主目录，稳定可读
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("pomo.log")
    }()

    static func write(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            // 超过 256KB 就截断重写，避免无限增长
            let size = (try? handle.seekToEnd()) ?? 0
            if size > 256 * 1024 {
                try? handle.truncate(atOffset: 0)
            }
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
