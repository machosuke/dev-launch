import XCTest
@testable import DevLaunch

final class IntegratedTerminalLauncherTests: XCTestCase {

    private var tempDir: URL!
    private var runningProcesses: [Process] = []

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for process in runningProcesses where process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        runningProcesses = []
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// /bin/sleep を argv[0] 偽装（exec -a）で起動する。
    /// バイナリをコピーして実行すると macOS のセキュリティ機構に SIGKILL される
    /// （プラットフォームバイナリのコピー実行は不可）ため、argv[0] で CLI 名を模す
    private func spawnSleep(argv0: String, cwd: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "exec -a \"$0\" /bin/sleep 30", argv0]
        process.currentDirectoryURL = cwd
        try process.run()
        runningProcesses.append(process)
        // exec 完了を待つ（zsh の起動は速いが確実にする）
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(process.isRunning, "fixture process died unexpectedly")
        return process
    }

    func testDetectsCliRunningInProject() throws {
        let projectDir = tempDir.appendingPathComponent("myproject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        _ = try spawnSleep(argv0: "claude", cwd: projectDir)

        XCTAssertTrue(
            IntegratedTerminalLauncher.isAICliRunning(named: "claude", inProjectAt: projectDir.path)
        )
    }

    func testDetectsVersionedCliBinaryViaPathComponent() throws {
        let projectDir = tempDir.appendingPathComponent("myproject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // claude 実体は ~/.local/share/claude/versions/2.1.206 のような
        // バージョン名バイナリとして動く。パス成分 "/claude/" で識別できること
        _ = try spawnSleep(argv0: "/fake/share/claude/versions/2.0.0", cwd: projectDir)

        XCTAssertTrue(
            IntegratedTerminalLauncher.isAICliRunning(named: "claude", inProjectAt: projectDir.path)
        )
    }

    func testDetectsCliRunningInSubdirectory() throws {
        let projectDir = tempDir.appendingPathComponent("myproject", isDirectory: true)
        let subDir = projectDir.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        _ = try spawnSleep(argv0: "claude", cwd: subDir)

        XCTAssertTrue(
            IntegratedTerminalLauncher.isAICliRunning(named: "claude", inProjectAt: projectDir.path)
        )
    }

    func testIgnoresCliRunningInDifferentProject() throws {
        let projectDir = tempDir.appendingPathComponent("myproject", isDirectory: true)
        let otherDir = tempDir.appendingPathComponent("otherproject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)

        _ = try spawnSleep(argv0: "claude", cwd: otherDir)

        XCTAssertFalse(
            IntegratedTerminalLauncher.isAICliRunning(named: "claude", inProjectAt: projectDir.path)
        )
    }

    func testIgnoresUnrelatedProcessInProject() throws {
        let projectDir = tempDir.appendingPathComponent("myproject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        _ = try spawnSleep(argv0: "someothertool", cwd: projectDir)

        XCTAssertFalse(
            IntegratedTerminalLauncher.isAICliRunning(named: "claude", inProjectAt: projectDir.path)
        )
    }

    func testSimilarProjectPathPrefixDoesNotMatch() throws {
        // /tmp/x/app で稼働中の CLI が /tmp/x/ap の起動をブロックしないこと
        let projectDir = tempDir.appendingPathComponent("app", isDirectory: true)
        let similarDir = tempDir.appendingPathComponent("ap", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: similarDir, withIntermediateDirectories: true)

        _ = try spawnSleep(argv0: "claude", cwd: projectDir)

        XCTAssertFalse(
            IntegratedTerminalLauncher.isAICliRunning(named: "claude", inProjectAt: similarDir.path)
        )
    }
}
