import Foundation
import ApplicationServices

struct IntegratedTerminalLauncher {

    enum LaunchError: LocalizedError {
        case editorNotFound(String)
        case accessibilityDenied
        case automationDenied
        case osascriptFailed(String)
        case freshShellNotFound

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
            case .freshShellNotFound:
                return "Could not confirm a fresh terminal shell. The AI CLI command was not typed to avoid disturbing existing sessions."
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
        // Step 0: 対象プロジェクトで AI CLI が既に稼働していれば、エディタを前面化するだけで
        // キー送信は行わない。ウィンドウタイトルや AX ツリーの状態（コールド起動直後は
        // ウィンドウ列挙が空になる）に依存しない、二重入力防止の最終ガード。
        let cliName = command.split(separator: " ").first.map(String.init) ?? command
        LaunchDiagnostics.log("launch start: project=\(projectPath) cli=\(cliName)")
        if let match = Self.runningAICliDescription(named: cliName, inProjectAt: projectPath) {
            LaunchDiagnostics.log("step0: CLI already running (\(match)) -> focus only, no keystrokes")
            try openEditor(editorApp: editorApp, projectPath: projectPath)
            return
        }
        LaunchDiagnostics.log("step0: no running CLI session detected")

        // Step 0.5: アクセシビリティ権限の事前チェック（ロケール非依存）
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
        LaunchDiagnostics.log("step1: window precheck = \(precheckResult)")
        if precheckResult == "reused" {
            LaunchDiagnostics.log("step1: existing window focused -> done, no keystrokes")
            return
        }

        // Step 2: エディタで新ウィンドウを開く
        try openEditor(editorApp: editorApp, projectPath: projectPath)

        // タイトルは一致するがパスを確認できないウィンドウ（"ambiguous"）が存在する場合、
        // それが「AI CLI 稼働中の同一プロジェクト」か「同名フォルダの別プロジェクト」かを
        // 区別できない。上の open はエディタ自身がパスベースで正しいウィンドウに集約する
        // ため誤爆しないが、キー送信は稼働中セッションへの二重入力になりうるためスキップする。
        if precheckResult == "ambiguous" {
            LaunchDiagnostics.log("step2: ambiguous window -> opened editor, no keystrokes")
            return
        }

        // Step 3: エディタの初期起動バッファ（ウィンドウ検出は AppleScript 側でポーリング）
        Thread.sleep(forTimeInterval: 1.5)

        // Step 4: プロジェクトウィンドウの出現を待って前面化する（キー送信はまだしない）
        _ = try runOsascript(
            script: Self.findProjectWindowScript,
            arguments: [folderName, editorProcessName, projectURLPrefix]
        )
        LaunchDiagnostics.log("step4: project window found and focused")

        // Step 5: 再チェック。Step 0 の判定以降（precheck・open・ウィンドウ出現待ちの間）に
        // AI CLI が起動していたら、ターミナルを開く前に中止する
        if let match = Self.runningAICliDescription(named: cliName, inProjectAt: projectPath) {
            LaunchDiagnostics.log("step5: CLI appeared (\(match)) -> abort before terminal")
            return
        }

        // Step 6: ターミナルパネルを開き、起動完了を待つ（キー送信はまだしない）
        let terminalRequestedAt = Date()
        _ = try runOsascript(
            script: Self.prepareTerminalScript,
            arguments: [folderName, editorProcessName, projectURLPrefix]
        )
        LaunchDiagnostics.log("step6: terminal panel opened")

        // Step 7: キー送信直前の最終再チェック。ターミナル起動待機（1.2秒）などの間に
        // AI CLI が起動していたら、コマンド入力を中止する
        if let match = Self.runningAICliDescription(named: cliName, inProjectAt: projectPath) {
            LaunchDiagnostics.log("step7: CLI appeared (\(match)) -> abort before typing")
            return
        }

        // Step 7.5: 「新品のシェル」ゲート（キー送信の必要条件）。
        // Step 6 のターミナル作成以降に生まれた、何も実行していないプロジェクト直下の
        // 対話シェルが確認できた場合のみキー送信する。稼働中の AI CLI を抱えるシェルは
        // 「子プロセスなし・作成直後」の条件を満たせないため、ウィンドウ検出や
        // CLI 検出がすべてすり抜けても、稼働中セッションへの打鍵は構造的に起きない。
        guard let shellPid = Self.waitForFreshShell(
            inProjectAt: projectPath,
            bornAfter: terminalRequestedAt,
            timeout: 6.0
        ) else {
            LaunchDiagnostics.log("step7.5: no fresh idle shell confirmed -> abort, no keystrokes")
            throw LaunchError.freshShellNotFound
        }
        LaunchDiagnostics.log("step7.5: fresh shell confirmed (pid=\(shellPid))")

        // Step 8: AI CLI コマンドを入力して実行する
        _ = try runOsascript(
            script: Self.typeCliCommandScript,
            arguments: [folderName, editorProcessName, command, projectURLPrefix]
        )
        LaunchDiagnostics.log("step8: command typed and submitted")

        // Step 9: 事後検証（情報記録のみ）。コマンドが実際に CLI を起動したかを確認する
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 1.0)
            if let match = Self.runningAICliDescription(named: cliName, inProjectAt: projectPath) {
                LaunchDiagnostics.log("step9: CLI startup verified (\(match))")
                return
            }
        }
        LaunchDiagnostics.log("step9: WARNING - CLI did not appear within 10s after typing")
    }

    // MARK: - Private

    /// エディタでプロジェクトを開く。既に同一フォルダのウィンドウがあれば
    /// エディタ自身がパスベースでそのウィンドウを前面化する（誤爆しない）。
    /// Process の arguments は配列で渡されるため、シェルインジェクションは発生しない
    private func openEditor(editorApp: String, projectPath: String) throws {
        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = ["-n", "-a", editorApp, "--args", "--new-window", projectPath]

        try openProcess.run()
        openProcess.waitUntilExit()

        guard openProcess.terminationStatus == 0 else {
            throw LaunchError.editorNotFound(editorApp)
        }
    }

    /// 指定した AI CLI がプロジェクトディレクトリ配下を作業ディレクトリとして
    /// 対話セッションとして稼働中かをプロセス走査で判定する。
    nonisolated static func isAICliRunning(named cliName: String, inProjectAt projectPath: String) -> Bool {
        runningAICliDescription(named: cliName, inProjectAt: projectPath) != nil
    }

    /// isAICliRunning の実体。稼働中なら「pid=... exe=... cwd=...」形式の説明
    /// 文字列（診断ログ用）を、いなければ nil を返す。
    ///
    /// CLI の実体は wrapper 経由でバージョン付きバイナリ（例:
    /// ~/.local/share/claude/versions/2.1.206）として動くことがあるため、
    /// 実行ファイル名の一致に加えて、パス成分に "/<cliName>/" を含む場合も
    /// 同一 CLI とみなす。判定は同一ユーザーのプロセスに限られる（proc_pidinfo
    /// は他ユーザーのプロセスでは失敗し、単にスキップされる）。
    nonisolated static func runningAICliDescription(named cliName: String, inProjectAt projectPath: String) -> String? {
        guard !cliName.isEmpty else { return nil }
        // カーネルが返す cwd はシンボリックリンク解決済みの実体パスなので、
        // 比較対象も realpath(3) で実体パスに揃える（例: /var/... → /private/var/...）。
        // Foundation の resolvingSymlinksInPath は /private プレフィックスを除去して
        // しまい逆方向の正規化になるため使えない
        let projectRoot = realProjectRoot(projectPath)

        var pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return nil }
        // 走査中のプロセス増加に備えて余裕を持たせる
        var pids = [pid_t](repeating: 0, count: Int(pidCount) * 2)
        pidCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard pidCount > 0 else { return nil }

        // 検出漏れの事後解析用: 名前と tty は一致したが cwd が違ったセッション
        var nearMisses: [String] = []

        for pid in pids.prefix(Int(pidCount)) where pid > 0 {
            guard let cwd = cwd(of: pid) else { continue }
            let cwdMatches = cwd == projectRoot || cwd.hasPrefix(projectRoot + "/")

            // CLI 名の照合（実行パス、なければ argv[0]）
            var matchedBy: String?
            var pathBuffer = [CChar](repeating: 0, count: 4096)
            if proc_pidpath(pid, &pathBuffer, 4096) > 0 {
                let executablePath = String(cString: pathBuffer)
                if matchesCli(path: executablePath, cliName: cliName) {
                    matchedBy = "exe=\(executablePath)"
                }
            }
            if matchedBy == nil,
               // node などのインタプリタ経由で動く CLI は実行ファイル名では判別できない
               // ため、argv[0]（起動時に指定されたコマンド名）でも照合する
               let argv0 = argv0(of: pid), matchesCli(path: argv0, cliName: cliName) {
                matchedBy = "argv0=\(argv0)"
            }
            guard let matchedBy else { continue }

            // 制御端末を持たないプロセスは対象外。AI CLI はデーモン・IDE 連携・
            // ヘッドレスセッション等の常駐プロセス（tty なし）を多数持ち、それらは
            // プロジェクトを cwd にしていても「ターミナルで対話中のセッション」では
            // ない。tty の有無が対話セッションと常駐プロセスの判別軸になる
            guard hasControllingTerminal(pid) else { continue }

            if cwdMatches {
                return "pid=\(pid) \(matchedBy) cwd=\(cwd)"
            }
            nearMisses.append("pid=\(pid) \(matchedBy) cwd=\(cwd)")
        }
        if !nearMisses.isEmpty {
            // 「稼働中なのに検出されなかった」報告が来たとき、cwd のずれが原因かを
            // 事後に判定できるよう、対象プロジェクト外の対話セッションを記録する
            LaunchDiagnostics.log("cli scan: no match for \(projectRoot); interactive sessions elsewhere: \(nearMisses.joined(separator: " | "))")
        }
        return nil
    }

    /// プロセスが制御端末を持つか（PROC_PIDTBSDINFO の pbi_flags で判定）。
    /// ターミナルで対話中のセッションだけが制御端末を持つ
    nonisolated private static func hasControllingTerminal(_ pid: pid_t) -> Bool {
        bsdInfo(of: pid).map { ($0.pbi_flags & UInt32(PROC_FLAG_CONTROLT)) != 0 } ?? false
    }

    nonisolated private static func bsdInfo(of pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    /// 「新品のアイドルシェル」を探す。条件:
    /// - 実行ファイル名が対話シェル（zsh/bash/fish/sh）
    /// - 制御端末を持つ（ターミナル内の対話シェル）
    /// - cwd がプロジェクト root に一致
    /// - bornAfter 以降に生まれた（＝Step 6 で作ったターミナルのシェル）
    /// - 子プロセスを持たない（＝まだ何も実行していない）
    /// 条件を満たす pid を返す。timeout まで 0.3 秒間隔でリトライする
    nonisolated static func waitForFreshShell(
        inProjectAt projectPath: String,
        bornAfter: Date,
        timeout: TimeInterval
    ) -> pid_t? {
        let deadline = Date().addingTimeInterval(timeout)
        // 秒単位の切り捨てだと最大1秒古いシェルを誤って「作成後」と判定するため、
        // pbi_start_tvsec/tvusec を合成してマイクロ秒精度で比較する
        let bornAfterMicros = UInt64(bornAfter.timeIntervalSince1970 * 1_000_000)
        let shellNames: Set<String> = ["zsh", "bash", "fish", "sh"]
        let projectRoot = realProjectRoot(projectPath)

        repeat {
            var pidCount = proc_listallpids(nil, 0)
            if pidCount > 0 {
                var pids = [pid_t](repeating: 0, count: Int(pidCount) * 2)
                pidCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
                let allPids = Array(pids.prefix(Int(max(pidCount, 0))))

                for pid in allPids where pid > 0 {
                    guard let info = bsdInfo(of: pid),
                          info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec >= bornAfterMicros,
                          (info.pbi_flags & UInt32(PROC_FLAG_CONTROLT)) != 0 else { continue }

                    var nameBuffer = [CChar](repeating: 0, count: 4096)
                    guard proc_pidpath(pid, &nameBuffer, 4096) > 0,
                          shellNames.contains((String(cString: nameBuffer) as NSString).lastPathComponent) else {
                        continue
                    }

                    guard cwd(of: pid) == projectRoot else { continue }

                    // 子プロセスを持つシェルは何かを実行中なので除外
                    let hasChild = allPids.contains { childPid in
                        childPid > 0 && childPid != pid && bsdInfo(of: childPid)?.pbi_ppid == UInt32(pid)
                    }
                    if !hasChild {
                        return pid
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return nil
    }

    nonisolated private static func cwd(of pid: pid_t) -> String? {
        var vnodeInfo = proc_vnodepathinfo()
        let infoSize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, infoSize) == infoSize else {
            return nil
        }
        return withUnsafeBytes(of: vnodeInfo.pvi_cdir.vip_path) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
    }

    /// プロジェクトパスをカーネルの返す cwd と比較可能な実体パスへ正規化する
    nonisolated private static func realProjectRoot(_ projectPath: String) -> String {
        var resolvedBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(projectPath, &resolvedBuffer) != nil {
            return String(cString: resolvedBuffer)
        }
        return URL(fileURLWithPath: projectPath).standardizedFileURL.path
    }

    /// 実行パス（または argv[0]）が対象 CLI を指すか。
    /// 末尾要素の一致に加え、パス成分に "/<cliName>/" を含む場合
    /// （例: ~/.local/share/claude/versions/2.1.206）も同一 CLI とみなす。
    nonisolated private static func matchesCli(path: String, cliName: String) -> Bool {
        (path as NSString).lastPathComponent == cliName || path.contains("/\(cliName)/")
    }

    /// KERN_PROCARGS2 で対象プロセスの argv[0] を取得する（同一ユーザーのみ可）。
    /// バッファ先頭は argc(Int32)、続いて実行パス + NUL パディング、その後に argv[0] が並ぶ
    nonisolated private static func argv0(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }

        var index = MemoryLayout<Int32>.size
        // 実行パスをスキップ
        while index < size, buffer[index] != 0 { index += 1 }
        // NUL パディングをスキップ
        while index < size, buffer[index] == 0 { index += 1 }
        guard index < size else { return nil }

        var end = index
        while end < size, buffer[end] != 0 { end += 1 }
        return String(bytes: buffer[index..<end], encoding: .utf8)
    }

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
            // 途中失敗が無音で消えると事後解析が不可能になるため必ず記録する
            LaunchDiagnostics.log("osascript failed (exit \(process.terminationStatus)): \(errorString.prefix(300))")
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
            -- AX ツリーが目覚めるまでウィンドウは空を返すことがあるため、
            -- 1件でも列挙できるまで最大3秒待つ（0件が実態ならタイムアウトで none）。
            -- wake は1回では効かないことがあるため各イテレーションで実行する
            repeat 6 times
                my wakeAccessibility(procName)
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

    /// argv: 1=folderName, 2=processName, 3=projectURLPrefix
    ///
    /// プロジェクトウィンドウの出現をポーリングで待ち、見つかったら前面化して "found" を
    /// 返す。キー送信は行わない（呼び出し側が AI CLI 稼働の最終再チェックを挟むため、
    /// ウィンドウ検出とキー送信は別スクリプトに分離している）。
    /// 見つからなければエラー終了する。
    private static let findProjectWindowScript = """
        on run argv
            set folderName to item 1 of argv
            set procName to item 2 of argv
            set urlPrefix to item 3 of argv

            -- ウィンドウ出現ポーリング（0.5秒間隔、最大8秒）
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

            if targetWindow is missing value then
                error "Target window not found for project: " & folderName
            end if

            my grabFocus(procName, targetWindow)
            return "found"
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

    /// argv: 1=folderName, 2=processName, 3=projectURLPrefix
    ///
    /// ターミナルパネルを開いて起動完了を待つ。AI CLI コマンドの入力は行わない
    /// （呼び出し側がターミナル起動待機の後にも AI CLI 稼働の最終再チェックを挟むため、
    /// ターミナル準備とコマンド入力は別スクリプトに分離している）。
    private static let prepareTerminalScript = """
        on run argv
            set folderName to item 1 of argv
            set procName to item 2 of argv
            set urlPrefix to item 3 of argv

            set targetWindow to my reacquireWindow(folderName, procName, urlPrefix)

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

            -- Phase 5: ターミナル起動待機
            delay 1.2
            return "ready"
        end run

        \(reacquireWindowHandlerScript)
        """

    /// argv: 1=folderName, 2=processName, 3=cliCommand, 4=projectURLPrefix
    ///
    /// このスクリプトは事前チェックが "none"、findProjectWindowScript でウィンドウを
    /// 前面化済み、prepareTerminalScript でターミナル準備済み、かつ直前の AI CLI 稼働
    /// 再チェックを通過した場合のみ実行される。すなわちタイトル一致かつパス不明
    /// （ambiguous）の既存ウィンドウは存在せず、同名タイトルの他ウィンドウが残っている
    /// とすればパス確認済みの別プロジェクト（foreign）だけである。そのため
    /// "same" / "ambiguous"（＝開いたばかりでファイル未フォーカスの新規ウィンドウ）のみを
    /// キー送信対象とすれば、別プロジェクトへの誤送信は起きない。
    private static let typeCliCommandScript = """
        on run argv
            set folderName to item 1 of argv
            set procName to item 2 of argv
            set cliCommand to item 3 of argv
            set urlPrefix to item 4 of argv

            set targetWindow to my reacquireWindow(folderName, procName, urlPrefix)

            -- Phase 6: フォーカス取得 → コマンド入力
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

        \(reacquireWindowHandlerScript)
        """

    /// prepareTerminalScript / typeCliCommandScript 共通のウィンドウ再取得ハンドラ。
    /// 直前の findProjectWindowScript で前面化済みのため短いポーリングで足りる。
    /// 見つからなければエラー終了する。grabFocus と照合ハンドラ群も同梱する。
    private static let reacquireWindowHandlerScript = """
        on reacquireWindow(folderName, procName, urlPrefix)
            set targetWindow to missing value
            repeat 10 times
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
                if targetWindow is not missing value then return targetWindow
                delay 0.2
            end repeat
            error "Target window not found for project: " & folderName
        end reacquireWindow

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
