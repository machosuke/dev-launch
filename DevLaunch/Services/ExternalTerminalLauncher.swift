import Foundation

struct ExternalTerminalLauncher {

    enum LaunchError: LocalizedError {
        case osascriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .osascriptFailed(let detail):
                return "Failed to open Terminal: \(detail)"
            }
        }
    }

    func launch(projectPath: String, command: String) throws {
        // AppleScript の quoted form of を使い、パスとコマンドを安全にシェルへ渡す。
        // Swift 側で文字列埋め込みせず、AppleScript 変数として受け取る。
        let appleScript = """
        on run argv
            set projectPath to item 1 of argv
            set cliCommand to item 2 of argv
            tell application "Terminal"
                activate
                do script "cd " & quoted form of projectPath & " && " & cliCommand
            end tell
        end run
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript, projectPath, command]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw LaunchError.osascriptFailed(errorString)
        }
    }
}
