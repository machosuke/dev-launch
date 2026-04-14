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
        case "zed":
            return ("Zed", "Zed")
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

        // Step 2 & 3: ウィンドウ待機 + ターミナル操作を一体化した AppleScript で実行
        // ポーリングでウィンドウの準備完了を確認してからキーストロークを送るため、
        // 固定待機中にユーザー操作でフォーカスが奪われる問題を解消する
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

        // 改善ポイント:
        // 1. ウィンドウ存在をポーリングで待機（固定5秒sleep廃止）
        // 2. すべてのキー操作を tell process 内で実行（フォーカス外へのキー送信防止）
        // 3. 各操作ブロック前に frontmost を再設定（途中のフォーカス奪取に対応）
        return """
        on run argv
            set folderName to item 1 of argv
            set procName to item 2 of argv
            set cliCommand to item 3 of argv

            -- Phase 1: エディタウィンドウがフォルダ名を含むまでポーリング（最大10秒）
            set windowFound to false
            repeat 40 times
                try
                    tell application "System Events"
                        tell process "\(safeProcessName)"
                            repeat with w in windows
                                if name of w contains folderName then
                                    set windowFound to true
                                    exit repeat
                                end if
                            end repeat
                        end tell
                    end tell
                end try
                if windowFound then exit repeat
                delay 0.25
            end repeat

            -- Phase 2: ウィンドウをアクティブ化してキーストロークを送信
            tell application "System Events"
                tell process "\(safeProcessName)"
                    set frontmost to true
                    repeat with w in windows
                        if name of w contains folderName then
                            perform action "AXRaise" of w
                            exit repeat
                        end if
                    end repeat
                    delay 0.2

                    -- IME を英数に切り替え
                    key code 102
                    delay 0.1

                    -- 新規ターミナルを開く
                    set frontmost to true
                    keystroke "`" using {control down, shift down}
                end tell
            end tell

            -- Phase 3: ターミナル準備待ち → コマンド入力
            delay 1.5
            tell application "System Events"
                tell process "\(safeProcessName)"
                    set frontmost to true
                    keystroke cliCommand
                    delay 0.2
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
