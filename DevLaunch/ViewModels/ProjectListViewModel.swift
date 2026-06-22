import AppKit
import Combine
import Foundation

enum SortOrder: String {
    case recentFirst
    case alphabetical
}

@MainActor
final class ProjectListViewModel: ObservableObject {
    @Published var sortOrder: SortOrder = .recentFirst
    @Published var searchText: String = ""
    @Published var searchFieldID = UUID()
    @Published var errorMessage: String?
    @Published var isLaunching: Bool = false
    @Published var launchingProjectPath: String?

    let scanner: ProjectScanner
    private let launcher: ProjectLauncher
    private var scannerSubscription: AnyCancellable?

    var hasScanFolder: Bool {
        UserDefaults.standard.string(forKey: AppStorageKey.scanFolderPath) != nil
    }

    var projects: [Project] {
        var source = scanner.projects

        if !searchText.isEmpty {
            source = source.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch sortOrder {
        case .recentFirst:
            return source.sorted {
                ($0.lastLaunchedAt ?? .distantPast) > ($1.lastLaunchedAt ?? .distantPast)
            }
        case .alphabetical:
            return source.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private var defaultsObserver: Any?

    init(scanner: ProjectScanner, launcher: ProjectLauncher) {
        self.scanner = scanner
        self.launcher = launcher
        loadSettings()

        // scanner の @Published 変更を ViewModel の objectWillChange に転送
        scannerSubscription = scanner.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        // 設定画面でのソート順変更を即反映
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadSettings()
            }
        }
    }

    // MARK: - Public

    func performScan() async {
        guard let path = UserDefaults.standard.string(forKey: AppStorageKey.scanFolderPath) else {
            return
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            errorMessage = "Scan folder not found. Please update in Settings."
            return
        }
        await scanner.scan(folderURL: url)
    }

    func selectScanFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to scan for Git projects"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        UserDefaults.standard.set(url.path, forKey: AppStorageKey.scanFolderPath)
        objectWillChange.send()
        NotificationCenter.default.post(name: .scanFolderDidChange, object: url)
    }

    func launch(_ project: Project) async {
        isLaunching = true
        launchingProjectPath = project.path
        errorMessage = nil

        do {
            try await launcher.launch(project)
            updateLastLaunched(for: project)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLaunching = false
        launchingProjectPath = nil
    }

    // MARK: - Private

    private func loadSettings() {
        if let raw = UserDefaults.standard.string(forKey: AppStorageKey.sortOrder),
           let order = SortOrder(rawValue: raw) {
            sortOrder = order
        }
    }

    private func updateLastLaunched(for project: Project) {
        var stored = UserDefaults.standard.dictionary(forKey: AppStorageKey.lastLaunchedDates)
            as? [String: Double] ?? [:]
        stored[project.path] = Date().timeIntervalSince1970
        UserDefaults.standard.set(stored, forKey: AppStorageKey.lastLaunchedDates)

        if let index = scanner.projects.firstIndex(where: { $0.path == project.path }) {
            scanner.projects[index].lastLaunchedAt = Date()
        }
    }
}
