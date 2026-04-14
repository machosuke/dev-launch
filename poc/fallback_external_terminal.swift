#!/usr/bin/env swift

import Foundation

// MARK: - Fallback: External Terminal (Terminal.app)
// Terminal.app の AppleScript `do script` で cd + claude を実行する
// アクセシビリティ権限不要・最も確実なアプローチ

let projectPath: String = {
    if CommandLine.arguments.count > 1 {
        return CommandLine.arguments[1]
    }
    // デフォルト: dev-launch プロジェクト自体
    return FileManager.default.currentDirectoryPath
}()

// パスの存在確認
guard FileManager.default.fileExists(atPath: projectPath) else {
    print("FAILURE: Path does not exist: \(projectPath)")
    exit(1)
}

let escapedPath = projectPath.replacingOccurrences(of: "'", with: "'\\''")
let appleScript = """
tell application "Terminal"
    activate
    do script "cd '\(escapedPath)' && claude"
end tell
"""

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
process.arguments = ["-e", appleScript]

let pipe = Pipe()
process.standardError = pipe

do {
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
        print("SUCCESS: fallback_external_terminal")
    } else {
        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorString = String(data: errorData, encoding: .utf8) ?? "unknown error"
        print("FAILURE: osascript exit code \(process.terminationStatus) - \(errorString)")
    }
} catch {
    print("FAILURE: \(error.localizedDescription)")
}
