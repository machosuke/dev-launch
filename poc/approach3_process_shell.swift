#!/usr/bin/env swift

import Foundation

// MARK: - Approach 3: Process + Shell Hybrid
// Approach 2 と同じロジックを単一シェルスクリプトで実行
// Phase 2 の ProjectLauncher.swift に最も近い実装形式
//
// 要件: アクセシビリティ権限

let projectPath: String = {
    if CommandLine.arguments.count > 1 {
        return CommandLine.arguments[1]
    }
    return FileManager.default.currentDirectoryPath
}()

let command: String = {
    if CommandLine.arguments.count > 2 {
        return CommandLine.arguments[2]
    }
    return "claude"
}()

guard FileManager.default.fileExists(atPath: projectPath) else {
    print("FAILURE: Path does not exist: \(projectPath)")
    exit(1)
}

let folderName = URL(fileURLWithPath: projectPath).lastPathComponent
let escapedPath = projectPath.replacingOccurrences(of: "'", with: "'\\''")
let escapedFolder = folderName.replacingOccurrences(of: "'", with: "'\\''")
let escapedCmd = command.replacingOccurrences(of: "'", with: "'\\''")

// 全手順を単一シェルスクリプトにまとめる
let shellScript = """
# Step 1: VS Code 新ウィンドウで開く
/usr/bin/open -n -a "Visual Studio Code" --args --new-window '\(escapedPath)'

# Step 2: ウィンドウロード待ち
sleep 5

# Step 3: AppleScript でウィンドウ特定 → IME切替 → ターミナル → コマンド
/usr/bin/osascript -e '
tell application "System Events"
    tell process "Code"
        set frontmost to true
        repeat with w in windows
            if name of w contains "\(escapedFolder)" then
                perform action "AXRaise" of w
                exit repeat
            end if
        end repeat
    end tell
end tell
delay 1
tell application "System Events"
    key code 102
    delay 0.5
    tell process "Code"
        keystroke "`" using {control down, shift down}
        delay 2
        keystroke "\(escapedCmd)"
        delay 0.3
        keystroke return
    end tell
end tell
'
"""

let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/zsh")
process.arguments = ["-c", shellScript]

let stderrPipe = Pipe()
process.standardError = stderrPipe

do {
    try process.run()
    process.waitUntilExit()

    let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    let errorString = String(data: errorData, encoding: .utf8) ?? ""

    if process.terminationStatus == 0 {
        print("SUCCESS: approach3_process_shell")
    } else if errorString.contains("not allowed assistive access") ||
              errorString.contains("accessibility") {
        print("FAILURE: Accessibility permission required.")
    } else {
        print("FAILURE: exit code \(process.terminationStatus) - \(errorString)")
    }
} catch {
    print("FAILURE: \(error.localizedDescription)")
}
