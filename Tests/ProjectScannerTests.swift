import XCTest
@testable import DevLaunch

@MainActor
final class ProjectScannerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testDetectsGitRepositories() async throws {
        let projectDir = tempDir.appendingPathComponent("myproject")
        let gitDir = projectDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let scanner = ProjectScanner()
        await scanner.scan(folderURL: tempDir)

        XCTAssertEqual(scanner.projects.count, 1)
        XCTAssertEqual(scanner.projects.first?.name, "myproject")
        XCTAssertTrue(scanner.projects.first?.path.hasSuffix("myproject") == true)
    }

    func testIgnoresFoldersWithoutGit() async throws {
        let nonGitDir = tempDir.appendingPathComponent("notaproject")
        try FileManager.default.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

        let scanner = ProjectScanner()
        await scanner.scan(folderURL: tempDir)

        XCTAssertEqual(scanner.projects.count, 0)
    }

    func testIgnoresHiddenFolders() async throws {
        let hiddenDir = tempDir.appendingPathComponent(".hidden")
        let gitDir = hiddenDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let scanner = ProjectScanner()
        await scanner.scan(folderURL: tempDir)

        XCTAssertEqual(scanner.projects.count, 0)
    }

    func testIgnoresFiles() async throws {
        let file = tempDir.appendingPathComponent("notadir.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let scanner = ProjectScanner()
        await scanner.scan(folderURL: tempDir)

        XCTAssertEqual(scanner.projects.count, 0)
    }

    func testDetectsMultipleProjects() async throws {
        for name in ["projectA", "projectB", "projectC"] {
            let gitDir = tempDir.appendingPathComponent(name).appendingPathComponent(".git")
            try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        }
        let nonGitDir = tempDir.appendingPathComponent("noGit")
        try FileManager.default.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

        let scanner = ProjectScanner()
        await scanner.scan(folderURL: tempDir)

        XCTAssertEqual(scanner.projects.count, 3)
    }

    func testIsScanningFalseAfterCompletion() async throws {
        let scanner = ProjectScanner()
        await scanner.scan(folderURL: tempDir)

        XCTAssertFalse(scanner.isScanning)
    }

    func testNonexistentFolderReturnsEmpty() async throws {
        let nonexistent = tempDir.appendingPathComponent("doesnotexist")

        let scanner = ProjectScanner()
        await scanner.scan(folderURL: nonexistent)

        XCTAssertEqual(scanner.projects.count, 0)
    }
}
