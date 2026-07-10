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

        let folderName = URL(fileURLWithPath: projectPath).lastPathComponent
        // ウィンドウの AXDocument（file:// URL）とのプレフィックス照合に使う。
        // isDirectory: true により末尾に "/" が付き、同名プレフィックスの別パス
        // （例: /work/app と /work/app2）の誤一致を防ぐ
        let projectURLPrefix = URL(fileURLWithPath: projectPath, isDirectory: true).absoluteString

        // Step 1: 同じプロジェクトのウィンドウが既に開いていればフォーカスのみで終了する。
        // VS Code / Cursor は同一フォルダを --new-window 指定でも既存ウィンドウに集約するため、
        // ここで止めないと稼働中の AI CLI セッションへ keystroke が二重入力される。
        // "reused" はパス確認済み（AXDocument 一致）の場合のみ返る。
        let precheckResult = try runOsascript(
            script: Self.focusExistingWindowScript,
            arguments: [folderName, editorProcessName, projectURLPrefix]
        )
        if precheckResult == "reused" {
            return
        }

        // Step 2: エディタで新ウィンドウを開く
        // Process の arguments は配列で渡されるため、シェルインジェクションは発生しない
        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = ["-n", "-a", editorApp, "--args", "--new-window", projectPath]

        try openProcess.run()
        openProcess.waitUntilExit()

        guard openProcess.terminationStatus == 0 else {
            throw LaunchError.editorNotFound(editorApp)
        }

        // タイトルは一致するがパスを確認できないウィンドウ（"ambiguous"）が存在する場合、
        // それが「AI CLI 稼働中の同一プロジェクト」か「同名フォルダの別プロジェクト」かを
        // 区別できない。上の open はエディタ自身がパスベースで正しいウィンドウに集約する
        // ため誤爆しないが、キー送信は稼働中セッションへの二重入力になりうるためスキップする。
        if precheckResult == "ambiguous" {
            return
        }

        // Step 3: エディタの初期起動バッファ（ウィンドウ検出は AppleScript 側でポーリング）
        Thread.sleep(forTimeInterval: 1.5)

        // Step 4: AppleScript でターミナルを開き AI CLI コマンドを入力する
        _ = try runOsascript(
            script: Self.launchScript,
            arguments: [folderName, editorProcessName, command, projectURLPrefix]
        )
    }

    // MARK: - Private

    /// osascript を実行し、stdout（末尾空白除去済み）を返す。
    /// 終了コード非0の場合は stderr を TCC 権限エラーへ分類して throw する。
    private func runOsascript(script: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errorString = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
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

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: outputData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// プロジェクトウィンドウの同一性判定ハンドラ（両スクリプト共通）。
    ///
    /// 1) タイトル照合: VS Code / Cursor の macOS ウィンドウタイトルは「フォルダ名」または
    ///    「ファイル名 — フォルダ名」形式（区切りは em dash）。単純な contains 照合だと
    ///    部分一致（例: "dev" が "dev-launch" のウィンドウに一致）で誤爆するため、
    ///    区切り文字を含めた境界付きで照合する。
    /// 2) パス照合: タイトルはフォルダ名しか持たないため、同名フォルダの別プロジェクト
    ///    （例: /a/app と /b/app）を区別できない。ウィンドウの AXDocument（フォーカス中
    ///    ファイルの file:// URL）がプロジェクトの URL プレフィックスに含まれるかで検証する。
    ///
    /// 戻り値: "same"（タイトル一致＋パス一致） / "ambiguous"（タイトル一致だがファイル
    /// 未フォーカスでパス不明） / "foreign"（タイトル一致だが別パスのファイルを表示中） /
    /// "no"（タイトル不一致）
    private static let matchHandlerScript = """
        on projectVerdict(winName, axDoc, folderName, urlPrefix)
            if not my matchesProject(winName, folderName) then return "no"
            if axDoc is missing value then return "ambiguous"
            set docText to axDoc as text
            if docText is "" then return "ambiguous"
            if docText starts with urlPrefix then return "same"
            return "foreign"
        end projectVerdict

        on matchesProject(winName, folderName)
            if winName is missing value then return false
            if winName is folderName then return true
            if winName ends with ("— " & folderName) then return true
            if winName starts with (folderName & " —") then return true
            if winName contains ("— " & folderName & " —") then return true
            return false
        end matchesProject

        on documentOf(w)
            tell application "System Events"
                try
                    return value of attribute "AXDocument" of w
                on error
                    return missing value
                end try
            end tell
        end documentOf

        -- Electron/Chromium 系アプリはアクセシビリティクライアントが接続するまで
        -- AX ツリーを構築せず、ウィンドウが実在しても windows が空を返すことがある。
        -- AXManualAccessibility / AXEnhancedUserInterface を立てて明示的に起こす。
        on wakeAccessibility(procName)
            tell application "System Events"
                if not (exists process procName) then return
                tell process procName
                    try
                        set value of attribute "AXManualAccessibility" to true
                    end try
                    try
                        set value of attribute "AXEnhancedUserInterface" to true
                    end try
                end tell
            end tell
        end wakeAccessibility
        """

    /// argv: 1=folderName, 2=processName, 3=projectURLPrefix
    /// パス確認済み（"same"）の既存ウィンドウがあれば前面化して "reused" を返す。
    /// タイトル一致だがパス未確認（AXDocument 欠落）のウィンドウのみ見つかった場合は、
    /// 同名フォルダの別プロジェクトの可能性を排除できないため、前面化もキー送信もせず
    /// "ambiguous" を返して呼び出し側に委ねる（open がパスベースで正しく処理する）。
    /// どちらもなければ "none" を返す。
    private static let focusExistingWindowScript = """
        on run argv
            set folderName to item 1 of argv
            set procName to item 2 of argv
            set urlPrefix to item 3 of argv
            tell application "System Events"
                if not (exists process procName) then return "none"
            end tell
            my wakeAccessibility(procName)
            -- AX ツリーが目覚めるまでウィンドウは空を返すことがあるため、
            -- 1件でも列挙できるまで最大3秒待つ（0件が実態ならタイムアウトで none）
            repeat 6 times
                set winCount to 0
                set sawAmbiguous to false
                tell application "System Events"
                    tell process procName
                        set wins to windows
                        set winCount to count of wins
                        repeat with w in wins
                            set verdict to my projectVerdict(name of w, my documentOf(w), folderName, urlPrefix)
                            if verdict is "same" then
                                set frontmost to true
                                perform action "AXRaise" of w
                                return "reused"
                            else if verdict is "ambiguous" then
                                set sawAmbiguous to true
                            end if
                        end repeat
                    end tell
                end tell
                if sawAmbiguous then return "ambiguous"
                if winCount > 0 then return "none"
                delay 0.5
            end repeat
            return "none"
        end run

        \(matchHandlerScript)
        """

    /// argv: 1=folderName, 2=processName, 3=cliCommand, 4=projectURLPrefix
    ///
    /// このスクリプトは事前チェックが "none" の場合のみ実行される。すなわちタイトル一致かつ
    /// パス不明（ambiguous）の既存ウィンドウは存在せず、同名タイトルの他ウィンドウが残って
    /// いるとすればパス確認済みの別プロジェクト（foreign）だけである。そのため
    /// "same" / "ambiguous"（＝開いたばかりでファイル未フォーカスの新規ウィンドウ）のみを
    /// キー送信対象とすれば、別プロジェクトへの誤送信は起きない。
    private static let launchScript = """
        on run argv
            set folderName to item 1 of argv
            set procName to item 2 of argv
            set cliCommand to item 3 of argv
            set urlPrefix to item 4 of argv

            -- Phase 1: ウィンドウ出現ポーリング（0.5秒間隔、最大8秒）
            -- 各イテレーションで AX ツリーを起こす（コールド起動直後は windows が空のため）
            set targetWindow to missing value
            repeat 16 times
                my wakeAccessibility(procName)
                tell application "System Events"
                    if exists process procName then
                        tell process procName
                            repeat with w in windows
                                set verdict to my projectVerdict(name of w, my documentOf(w), folderName, urlPrefix)
                                if verdict is "same" or verdict is "ambiguous" then
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

            -- Phase 2: ウィンドウを前面に（キーバインド初期化の待機を兼ねる）
            my grabFocus(procName, targetWindow)
            delay 0.5

            -- Phase 3: フォーカス再取得 → IME切替（英数キー）
            my grabFocus(procName, targetWindow)
            tell application "System Events"
                key code 102
            end tell
            delay 0.3

            -- Phase 4: フォーカス再取得 → ターミナルを開く
            my grabFocus(procName, targetWindow)
            tell application "System Events"
                tell process procName
                    keystroke "`" using {control down, shift down}
                end tell
            end tell

            -- Phase 5: ターミナル起動待機 → フォーカス再取得
            delay 1.2
            my grabFocus(procName, targetWindow)

            -- Phase 6: フォーカス再取得 → コマンド入力
            my grabFocus(procName, targetWindow)
            tell application "System Events"
                tell process procName
                    keystroke cliCommand
                end tell
            end tell
            delay 0.2

            -- Phase 7: フォーカス再取得 → Enter実行
            my grabFocus(procName, targetWindow)
            tell application "System Events"
                tell process procName
                    keystroke return
                end tell
            end tell
        end run

        on grabFocus(procName, targetWin)
            tell application "System Events"
                tell process procName
                    set frontmost to true
                    perform action "AXRaise" of targetWin
                end tell
            end tell
            delay 0.1
        end grabFocus

        \(matchHandlerScript)
        """
}
