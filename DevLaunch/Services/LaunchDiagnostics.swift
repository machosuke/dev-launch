import Foundation

/// 起動フローの判断を記録する診断ログ。
/// 「コマンドが入らない」「二重に入る」等の報告時に、どの分岐で
/// その挙動になったかを事後に特定するために全ステップを記録する。
/// 出力先: ~/Library/Logs/DevLaunch.log（Console.app やエディタで閲覧可能）
enum LaunchDiagnostics {

    private static let queue = DispatchQueue(label: "com.machosuke.DevLaunch.diagnostics")

    private static let logURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DevLaunch.log")

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// 5MB を超えたら旧ログを .old に退避する
    private static let maxLogSize: UInt64 = 5 * 1024 * 1024

    static func log(_ message: String) {
        let line = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
        queue.async {
            rotateIfNeeded()
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    private static func rotateIfNeeded() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.size] as? UInt64,
              size > maxLogSize else { return }
        let oldURL = logURL.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: logURL, to: oldURL)
    }
}
