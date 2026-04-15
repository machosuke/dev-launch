import Foundation

@MainActor
final class ProjectLauncher {

    enum LaunchError: LocalizedError {
        case editorCommandNotFound(String)
        case aiCliCommandNotFound(String)

        var errorDescription: String? {
            switch self {
            case .editorCommandNotFound(let cmd):
                return "Editor not found: \"\(cmd)\". Please check Settings."
            case .aiCliCommandNotFound(let cmd):
                return "AI CLI not found: \"\(cmd)\". Please check Settings."
            }
        }
    }

    private var editorCommand: String {
        UserDefaults.standard.string(forKey: AppStorageKey.editorCommand) ?? "code"
    }

    private var aiCliCommand: String {
        UserDefaults.standard.string(forKey: AppStorageKey.aiCliCommand) ?? "claude"
    }

    private var aiCliOptions: String {
        UserDefaults.standard.string(forKey: AppStorageKey.aiCliOptions) ?? ""
    }

    private var usesIntegratedTerminal: Bool {
        UserDefaults.standard.object(forKey: AppStorageKey.usesIntegratedTerminal) != nil
            ? UserDefaults.standard.bool(forKey: AppStorageKey.usesIntegratedTerminal)
            : true
    }

    private let integratedLauncher = IntegratedTerminalLauncher()
    private let externalLauncher = ExternalTerminalLauncher()

    func launch(_ project: Project) async throws {
        let editor = editorCommand
        let aiCli = aiCliCommand
        let options = aiCliOptions
        let useIntegrated = usesIntegratedTerminal

        guard resolveCommand(editor) != nil else {
            throw LaunchError.editorCommandNotFound(editor)
        }
        guard resolveCommand(aiCli) != nil else {
            throw LaunchError.aiCliCommandNotFound(aiCli)
        }

        let safeOptions = sanitizeOptions(options)
        let fullCliCommand = safeOptions.isEmpty ? aiCli : "\(aiCli) \(safeOptions)"

        try await Task.detached(priority: .userInitiated) { [integratedLauncher, externalLauncher] in
            if useIntegrated {
                let info = IntegratedTerminalLauncher.editorInfo(for: editor)
                try integratedLauncher.launch(
                    projectPath: project.path,
                    editorApp: info.appName,
                    editorProcessName: info.processName,
                    command: fullCliCommand
                )
            } else {
                // エディタを先に開く
                let openProcess = Process()
                openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                openProcess.arguments = ["-a", IntegratedTerminalLauncher.editorInfo(for: editor).appName, project.path]
                try openProcess.run()
                openProcess.waitUntilExit()

                // 外部ターミナルで AI CLI 起動
                try externalLauncher.launch(
                    projectPath: project.path,
                    command: fullCliCommand
                )
            }
        }.value
    }

    // MARK: - Private

    /// Removes tokens containing shell metacharacters from a free-form options string.
    nonisolated private func sanitizeOptions(_ options: String) -> String {
        let dangerousChars = CharacterSet(charactersIn: ";|&$`\"'\\(){}[]<>!\n\r")
        let tokens = options.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let safeTokens = tokens.filter { token in
            token.rangeOfCharacter(from: dangerousChars) == nil
        }
        return safeTokens.joined(separator: " ")
    }

    nonisolated private func resolveCommand(_ command: String) -> String? {
        // 絶対パスの場合はそのまま確認
        if command.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }

        // basename のみを許可（スラッシュ・シェルメタ文字を含むコマンドを拒否）
        let invalidChars = CharacterSet(charactersIn: "/;|&$`\"'\\(){}[]<>!\n\r\t ")
        guard command.rangeOfCharacter(from: invalidChars) == nil, !command.isEmpty else {
            return nil
        }

        // シェルを経由せず、PATH を直接分割して検索する
        let pathDirs = searchPaths()
        for dir in pathDirs {
            let fullPath = (dir as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }

    /// ログインシェルの PATH を取得する
    nonisolated private func searchPaths() -> [String] {
        // ProcessInfo の PATH はアプリバンドル起動時に限定的なので、
        // ログインシェルから PATH を取得する
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "echo $PATH"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return defaultPaths
        }

        guard process.terminationStatus == 0 else { return defaultPaths }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var paths = output.split(separator: ":").map(String.init)
        if paths.isEmpty { return defaultPaths }

        // アプリバンドルから起動した zsh はユーザープロファイルをロードしない場合があるため、
        // defaultPaths に含まれるディレクトリを補完する
        for defaultPath in defaultPaths {
            if !paths.contains(defaultPath) {
                paths.append(defaultPath)
            }
        }
        return paths
    }

    private nonisolated var defaultPaths: [String] {
        [
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/opt/homebrew/bin",
            NSHomeDirectory() + "/.local/bin",
        ]
    }
}
