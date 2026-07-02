import Foundation
import ApplicationServices

struct IntegratedTerminalLauncher {

    enum LaunchError: LocalizedError {
        case editorNotFound(String)
        case accessibilityDenied
        case automationDenied
        case osascriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .editorNotFound(let name):
                return "Editor not found: \(name). Please check Settings."
            case .accessibilityDenied:
                return "Accessibility permission required. Please grant access in System Settings > Privacy & Security > Accessibility."
            case .automationDenied:
                return "Automation permission required. Please allow DevLaunch to control \"System Events\" in System Settings > Privacy & Security > Automation."
            case .osascriptFailed(let detail):
                return "Failed to send keystrokes to editor: \(detail)"
            }
        }
    }

    /// エディタコマンドからアプリ名・プロセス名を解決する
    static func editorInfo(for command: String) -> (appName: String, processName: String)? {
        switch command {
        case "code":
            return ("Visual Studio Code", "Code")
        case "cursor":
            return ("Cursor", "Cursor")
        default:
            return nil
        }
    }

    func launch(
        projectPath: String,
        editorApp: String,
        editorProcessName: String,
        command: String
    ) throws {
        // Step 0: アクセシビリティ権限の事前チェック（ロケール非依存）
        // 未付与ならシステムの許可ダイアログを表示し、キー送信を試みる前に中断する
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        guard trusted else {
            throw LaunchError.accessibilityDenied
        }

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

        // Step 2: エディタの初期起動バッファ（ウィンドウ検出は AppleScript 側でポーリング）
        Thread.sleep(forTimeInterval: 1.5)

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
            // エラーメッセージ本文は OS の言語設定でローカライズされるため、
            // 文言マッチに加えてロケール非依存のエラーコードでも判定する
            // -25211 / 1002: assistive access（アクセシビリティ）拒否
            // -1743: Apple Events（オートメーション）拒否
            if errorString.contains("assistive access")
                || errorString.contains("accessibility")
                || errorString.contains("(-25211)")
                || errorString.contains("(1002)") {
                throw LaunchError.accessibilityDenied
            }
            if errorString.contains("(-1743)")
                || errorString.contains("Not authorized to send Apple events") {
                throw LaunchError.automationDenied
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

            -- Phase 1: ウィンドウ出現ポーリング（0.5秒間隔、最大8秒）
            set targetWindow to missing value
            repeat 16 times
                tell application "System Events"
                    if exists process "\(safeProcessName)" then
                        tell process "\(safeProcessName)"
                            repeat with w in windows
                                if name of w contains folderName then
                                    set targetWindow to w
                                    exit repeat
                                end if
                            end repeat
                        end tell
                    end if
                end tell
                if targetWindow is not missing value then exit repeat
                delay 0.5
            end repeat

            -- ウィンドウが見つからなければエラー終了
            if targetWindow is missing value then
                error "Target window not found for project: " & folderName
            end if

            -- フォーカス取得ハンドラ
            script FocusHelper
                on grabFocus(procName, targetWin)
                    tell application "System Events"
                        tell process procName
                            set frontmost to true
                            perform action "AXRaise" of targetWin
                        end tell
                    end tell
                    delay 0.1
                end grabFocus
            end script

            -- Phase 2: ウィンドウを前面に
            FocusHelper's grabFocus("\(safeProcessName)", targetWindow)
            delay 0.2

            -- Phase 3: フォーカス再取得 → IME切替（英数キー）
            FocusHelper's grabFocus("\(safeProcessName)", targetWindow)
            tell application "System Events"
                key code 102
            end tell
            delay 0.3

            -- Phase 4: フォーカス再取得 → ターミナルを開く
            FocusHelper's grabFocus("\(safeProcessName)", targetWindow)
            tell application "System Events"
                tell process "\(safeProcessName)"
                    keystroke "`" using {control down, shift down}
                end tell
            end tell

            -- Phase 5: ターミナル起動待機 → フォーカス再取得
            delay 1.2
            FocusHelper's grabFocus("\(safeProcessName)", targetWindow)

            -- Phase 6: フォーカス再取得 → コマンド入力
            FocusHelper's grabFocus("\(safeProcessName)", targetWindow)
            tell application "System Events"
                tell process "\(safeProcessName)"
                    keystroke cliCommand
                end tell
            end tell
            delay 0.2

            -- Phase 7: フォーカス再取得 → Enter実行
            FocusHelper's grabFocus("\(safeProcessName)", targetWindow)
            tell application "System Events"
                tell process "\(safeProcessName)"
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
