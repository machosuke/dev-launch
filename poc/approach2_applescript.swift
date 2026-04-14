#!/usr/bin/env swift

import Foundation

// MARK: - Approach 2: AppleScript Keystroke Sending (Validated)
// 1. open -n で VS Code 新ウィンドウを開く
// 2. System Events AXRaise でウィンドウ特定
// 3. 英数キーで IME 切替
// 4. Ctrl+Shift+` で新規ターミナル作成
// 5. キーストロークでコマンド入力
//
// 要件: アクセシビリティ権限（System Events キーストローク送信に必要）

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

// プロジェクトフォルダ名を取得（ウィンドウタイトル検索用）
let folderName = URL(fileURLWithPath: projectPath).lastPathComponent

// Step 1: VS Code で新しいウィンドウを開く
// open -n で新しいインスタンスのウィンドウを確実に開く
let openProcess = Process()
openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
openProcess.arguments = ["-n", "-a", "Visual Studio Code", "--args", "--new-window", projectPath]

do {
    try openProcess.run()
    openProcess.waitUntilExit()
    guard openProcess.terminationStatus == 0 else {
        print("FAILURE: Could not open VS Code (exit code: \(openProcess.terminationStatus))")
        exit(1)
    }
} catch {
    print("FAILURE: \(error.localizedDescription)")
    exit(1)
}

// Step 2: VS Code の新ウィンドウがロードされるまで待機
print("Waiting 5 seconds for VS Code new window to load...")
Thread.sleep(forTimeInterval: 5.0)

// Step 3: AppleScript でウィンドウ特定 → IME切替 → ターミナル作成 → コマンド入力
let escapedFolderName = folderName.replacingOccurrences(of: "\"", with: "\\\"")
let escapedCommand = command.replacingOccurrences(of: "\"", with: "\\\"")

let appleScript = """
tell application "System Events"
    tell process "Code"
        set frontmost to true
        -- ウィンドウをタイトルで特定して最前面に
        repeat with w in windows
            if name of w contains "\(escapedFolderName)" then
                perform action "AXRaise" of w
                exit repeat
            end if
        end repeat
    end tell
end tell
delay 1

tell application "System Events"
    -- 英数キーで IME を英語に切り替え
    key code 102
    delay 0.5

    tell process "Code"
        -- Ctrl+Shift+` で新規ターミナル作成（トグルではなく新規）
        keystroke "`" using {control down, shift down}
        delay 2
        -- コマンド入力
        keystroke "\(escapedCommand)"
        delay 0.3
        keystroke return
    end tell
end tell
"""

let osascriptProcess = Process()
osascriptProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
osascriptProcess.arguments = ["-e", appleScript]

let stderrPipe = Pipe()
osascriptProcess.standardError = stderrPipe

do {
    try osascriptProcess.run()
    osascriptProcess.waitUntilExit()

    let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    let errorString = String(data: errorData, encoding: .utf8) ?? ""

    if osascriptProcess.terminationStatus == 0 {
        print("SUCCESS: approach2_applescript")
    } else if errorString.contains("not allowed assistive access") ||
              errorString.contains("accessibility") {
        print("FAILURE: Accessibility permission required. Add Terminal.app to System Settings > Privacy & Security > Accessibility")
    } else {
        print("FAILURE: osascript exit code \(osascriptProcess.terminationStatus) - \(errorString)")
    }
} catch {
    print("FAILURE: \(error.localizedDescription)")
}
