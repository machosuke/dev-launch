import Foundation

struct IntegratedTerminalLauncher {

    enum LaunchError: LocalizedError {
        case editorNotFound(String)
        case accessibilityDenied
        case osascriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .editorNotFound(let name):
                return "Editor not found: \(name). Please check Settings."
            case .accessibilityDenied:
                return "Accessibility permission required. Please grant access in System Settings > Privacy & Security > Accessibility."
            case .osascriptFailed(let detail):
                return "Failed to send keystrokes to editor: \(detail)"
            }
        }
    }

    /// エディタコマンドからアプリ名・プロセス名を解決する
    static func editorInfo(for command: String) -> (appName: String, processName: String) {
        switch command {
        case "code":
            return ("Visual Studio Code", "Code")
        case "cursor":
            return ("Cursor", "Cursor")
        default:
            return ("Visual Studio Code", "Code")
        }
    }

    func launch(
        projectPath: String,
        editorApp: String,
        editorProcessName: String,
        command: String
    ) throws {
        // Step 1: エディタで新ウィンドウを開く
        // Process の arguments は配列で渡されるため、シェルインジェクションは発生しない
        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = ["-n", "-a", editorApp, "--args", "--new-window", projectPath]

        try openProcess.run()
        openProcess.waitUntilExit()

        guard openProcess.terminationStatus == 0 else {
            throw LaunchError.editorNotFound(editorApp)
        }

        // Step 2: エディタのウィンドウロード完了を待機
        Thread.sleep(forTimeInterval: 5.0)

        // Step 3: AppleScript でターミナル操作
        // folderName と command は osascript の引数として渡し、AppleScript 内で変数として受け取る
        let folderName = URL(fileURLWithPath: projectPath).lastPathComponent
        let appleScript = buildAppleScript(editorProcessName: editorProcessName)

        let osascriptProcess = Process()
        osascriptProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascriptProcess.arguments = ["-e", appleScript, folderName, editorProcessName, command]

        let stderrPipe = Pipe()
        osascriptProcess.standardError = stderrPipe

        try osascriptProcess.run()
        osascriptProcess.waitUntilExit()

        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errorString = String(data: errorData, encoding: .utf8) ?? ""

        if osascriptProcess.terminationStatus != 0 {
            if errorString.contains("assistive access") || errorString.contains("accessibility") {
                throw LaunchError.accessibilityDenied
            }
            throw LaunchError.osascriptFailed(errorString)
        }
    }

    // MARK: - Private

    private func buildAppleScript(editorProcessName: String) -> String {
        // osascript の引数: argv 1=folderName, 2=processName, 3=command
        // editorProcessName は静的マッピングで安全値のみ取りうるため直接埋め込み可
        let safeProcessName = escapeForAppleScript(editorProcessName)

        return """
        on run argv
            set folderName to item 1 of argv
            set procName to item 2 of argv
            set cliCommand to item 3 of argv
            tell application "System Events"
                tell process "\(safeProcessName)"
                    set frontmost to true
                    repeat with w in windows
                        if name of w contains folderName then
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
                tell process "\(safeProcessName)"
                    keystroke "`" using {control down, shift down}
                    delay 2
                    keystroke cliCommand
                    delay 0.3
                    keystroke return
                end tell
            end tell
        end run
        """
    }

    /// AppleScript 文字列リテラル用エスケープ
    private func escapeForAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
