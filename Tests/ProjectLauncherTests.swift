import XCTest
@testable import DevLaunch

final class ProjectLauncherTests: XCTestCase {

    func testBuildCommandWithFlagsOnly() {
        XCTAssertEqual(
            ProjectLauncher.buildAICliCommand(
                command: "claude",
                options: "--dangerously-skip-permissions"
            ),
            "claude --dangerously-skip-permissions"
        )
    }

    func testBuildCommandRemovesDuplicatedExecutableFromFullCommandOptions() {
        XCTAssertEqual(
            ProjectLauncher.buildAICliCommand(
                command: "claude",
                options: "claude --dangerously-skip-permissions"
            ),
            "claude --dangerously-skip-permissions"
        )
    }

    func testBuildCommandRemovesDuplicatedExecutableBasename() {
        XCTAssertEqual(
            ProjectLauncher.buildAICliCommand(
                command: "/usr/local/bin/claude",
                options: "claude --dangerously-skip-permissions"
            ),
            "/usr/local/bin/claude --dangerously-skip-permissions"
        )
    }

    func testBuildCommandPreservesNonCommandPositionalOption() {
        XCTAssertEqual(
            ProjectLauncher.buildAICliCommand(command: "claude", options: "--model opus"),
            "claude --model opus"
        )
    }

    func testBuildCommandStillRemovesUnsafeOptionTokens() {
        XCTAssertEqual(
            ProjectLauncher.buildAICliCommand(
                command: "claude",
                options: "claude --safe bad;command --verbose"
            ),
            "claude --safe --verbose"
        )
    }
}
