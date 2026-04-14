import Combine
import CoreServices
import Foundation

// MARK: - AppStorage Keys

enum AppStorageKey {
    static let scanFolderPath = "scanFolderPath"
    static let sortOrder = "sortOrder"
    static let editorCommand = "editorCommand"
    static let aiCliCommand = "aiCliCommand"
    static let aiCliOptions = "aiCliOptions"
    static let usesIntegratedTerminal = "usesIntegratedTerminal"
    static let lastLaunchedDates = "lastLaunchedDates"
    static let launchAtLogin = "launchAtLogin"
    static let globalShortcutKeyCode = "globalShortcutKeyCode"
    static let globalShortcutModifiers = "globalShortcutModifiers"
}

// MARK: - ProjectScanner

@MainActor
final class ProjectScanner: ObservableObject {
    @Published var projects: [Project] = []
    @Published private(set) var isScanning: Bool = false

    private var eventStream: FSEventStreamRef?
    private var scanFolderURL: URL?

    deinit {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: - Public API

    func scan(folderURL: URL) async {
        isScanning = true
        scanFolderURL = folderURL

        let scannedProjects = performScan(at: folderURL)
        projects = mergeWithStoredDates(scannedProjects)

        stopWatching()
        startWatching(folderURL: folderURL)

        isScanning = false
    }

    func stopWatching() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }

    // MARK: - Private: Scan

    nonisolated private func performScan(at url: URL) -> [Project] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { itemURL in
            guard let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]),
                  resourceValues.isDirectory == true else {
                return nil
            }

            let gitDir = itemURL.appendingPathComponent(".git")
            guard fileManager.fileExists(atPath: gitDir.path) else {
                return nil
            }

            return Project(path: itemURL.path)
        }
    }

    private func mergeWithStoredDates(_ scanned: [Project]) -> [Project] {
        let stored = UserDefaults.standard.dictionary(forKey: AppStorageKey.lastLaunchedDates)
            as? [String: Double] ?? [:]

        return scanned.map { project in
            var merged = project
            if let timestamp = stored[project.path] {
                merged.lastLaunchedAt = Date(timeIntervalSince1970: timestamp)
            }
            return merged
        }
    }

    // MARK: - Private: FSEvents

    private func startWatching(folderURL: URL) {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: selfPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [folderURL.path as CFString] as CFArray

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        eventStream = stream
    }

    fileprivate func handleFSEvent() {
        guard let folderURL = scanFolderURL else { return }
        let scannedProjects = performScan(at: folderURL)
        projects = mergeWithStoredDates(scannedProjects)
    }
}

// MARK: - FSEvents C Callback

private func fsEventCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let scanner = Unmanaged<ProjectScanner>.fromOpaque(info).takeUnretainedValue()
    Task { @MainActor in
        scanner.handleFSEvent()
    }
}
