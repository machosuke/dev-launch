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
    /// （プラットフォームバイナリのコピー実行は不可）ため、argv[0] で CLI 名を模す。
    ///
    /// withTty: true の場合は /usr/bin/script 経由で疑似端末（pty）を割り当てて起動する。
    /// 検出対象の「ターミナルで対話中のセッション」は制御端末を持つため、
    /// 検出されるべきフィクスチャは pty 付きで作る必要がある。
    @discardableResult
    private func spawnSleep(argv0: String, cwd: URL, withTty: Bool = true) throws -> Process {
        let process = Process()
        if withTty {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            process.arguments = ["-q", "/dev/null", "/bin/zsh", "-c", "exec -a \"$0\" /bin/sleep 30", argv0]
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "exec -a \"$0\" /bin/sleep 30", argv0]
        }
        process.currentDirectoryURL = cwd
        try process.run()
        runningProcesses.append(process)
        // exec 完了を待つ（zsh の起動は速いが確実にする）
        Thread.sleep(forTimeInterval: 0.5)
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

    func testIgnoresBackgroundProcessWithoutTty() throws {
        // 名前・cwd が一致しても、制御端末を持たないプロセス（デーモン・IDE 連携・
        // ヘッドレスセッション等のバックグラウンド常駐）は検出しないこと
        let projectDir = tempDir.appendingPathComponent("myproject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        try spawnSleep(argv0: "claude", cwd: projectDir, withTty: false)

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

    func testFreshShellIsFoundForIdleNewShell() throws {
        let projectDir = tempDir.appendingPathComponent("myproject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let bornAfter = Date().addingTimeInterval(-1)

        // pty 付きのアイドル対話シェル（script が pty を割り当てて zsh を起動する）
        let idle = Process()
        idle.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        idle.arguments = ["-q", "/dev/null", "/bin/zsh", "-f", "-i"]
        idle.standardInput = Pipe()  // 入力を保留したまま対話シェルをアイドルで維持
        idle.currentDirectoryURL = projectDir
        try idle.run()
        runningProcesses.append(idle)
        Thread.sleep(forTimeInterval: 0.5)

        let found = IntegratedTerminalLauncher.waitForFreshShell(
            inProjectAt: projectDir.path,
            bornAfter: bornAfter,
            timeout: 3.0
        )
        XCTAssertNotNil(found, "idle new shell should be detected as fresh")
    }

    func testFreshShellRejectsBusyShell() throws {
        let projectDir = tempDir.appendingPathComponent("myproject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let bornAfter = Date().addingTimeInterval(-1)

        // 子プロセス（sleep）を実行中のシェルは fresh ではない
        let busy = Process()
        busy.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        busy.arguments = ["-q", "/dev/null", "/bin/zsh", "-c", "/bin/sleep 30 & wait"]
        busy.currentDirectoryURL = projectDir
        try busy.run()
        runningProcesses.append(busy)
        Thread.sleep(forTimeInterval: 0.5)

        let found = IntegratedTerminalLauncher.waitForFreshShell(
            inProjectAt: projectDir.path,
            bornAfter: bornAfter,
            timeout: 1.5
        )
        XCTAssertNil(found, "shell with a running child must not be treated as fresh")
    }

    func testFreshShellRejectsOldShell() throws {
        let projectDir = tempDir.appendingPathComponent("myproject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let idle = Process()
        idle.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        idle.arguments = ["-q", "/dev/null", "/bin/zsh", "-f", "-i"]
        idle.standardInput = Pipe()
        idle.currentDirectoryURL = projectDir
        try idle.run()
        runningProcesses.append(idle)
        Thread.sleep(forTimeInterval: 0.5)

        // シェルの誕生より後の時刻を bornAfter に指定 → 古いシェルは対象外
        let found = IntegratedTerminalLauncher.waitForFreshShell(
            inProjectAt: projectDir.path,
            bornAfter: Date().addingTimeInterval(2),
            timeout: 1.0
        )
        XCTAssertNil(found, "shell born before the terminal request must be ignored")
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
