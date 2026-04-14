import SwiftUI

struct ProjectListView: View {
    @ObservedObject var viewModel: ProjectListViewModel
    @State private var selectedProjectPath: String?

    var body: some View {
        let projects = viewModel.projects

        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                ErrorBannerView(message: error) {
                    viewModel.errorMessage = nil
                }
            }

            if !viewModel.hasScanFolder {
                EmptyStateView {
                    viewModel.selectScanFolder()
                }
            } else if viewModel.scanner.isScanning {
                VStack {
                    Spacer()
                    ProgressView("Scanning\u{2026}")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if projects.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No Git projects found")
                        .font(.headline)
                    Text("No folders with .git were found in the selected directory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(projects) { project in
                            ProjectRowView(
                                project: project,
                                isLaunching: viewModel.launchingProjectPath == project.path,
                                isSelected: selectedProjectPath == project.path
                            ) {
                                selectedProjectPath = project.path
                                Task { await launch(project) }
                            }

                            if project.id != projects.last?.id {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 340)
            }

            Divider()

            HStack {
                Picker("", selection: $viewModel.sortOrder) {
                    Text("Recent").tag(SortOrder.recentFirst)
                    Text("A-Z").tag(SortOrder.alphabetical)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 120)

                Spacer()

                Button {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 300, height: 400)
        .background(
            KeyboardShortcutCaptureView { event in
                handleKeyDown(event)
            }
        )
        .onAppear {
            syncSelection(with: projects)
        }
        .onChange(of: projects) { newProjects in
            syncSelection(with: newProjects)
        }
        .task {
            if viewModel.hasScanFolder {
                await viewModel.performScan()
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let projects = viewModel.projects

        switch event.keyCode {
        case 126: // Up arrow
            moveSelection(by: -1, in: projects)
            return true
        case 125: // Down arrow
            moveSelection(by: 1, in: projects)
            return true
        case 36, 76: // Return, keypad Enter
            if let project = selectedProject(in: projects) {
                Task { await launch(project) }
            } else if !viewModel.hasScanFolder {
                viewModel.selectScanFolder()
            }
            return true
        case 53: // Escape
            NotificationCenter.default.post(name: .popoverShouldClose, object: nil)
            return true
        default:
            return false
        }
    }

    private func moveSelection(by offset: Int, in projects: [Project]) {
        guard !projects.isEmpty else {
            selectedProjectPath = nil
            return
        }

        guard let selectedProjectPath,
              let currentIndex = projects.firstIndex(where: { $0.path == selectedProjectPath }) else {
            selectedProjectPath = projects.first?.path
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), projects.count - 1)
        self.selectedProjectPath = projects[nextIndex].path
    }

    private func selectedProject(in projects: [Project]) -> Project? {
        guard let selectedProjectPath else { return projects.first }
        return projects.first { $0.path == selectedProjectPath } ?? projects.first
    }

    private func syncSelection(with projects: [Project]) {
        guard !projects.isEmpty else {
            selectedProjectPath = nil
            return
        }

        if let selectedProjectPath,
           projects.contains(where: { $0.path == selectedProjectPath }) {
            return
        }

        selectedProjectPath = projects.first?.path
    }

    private func launch(_ project: Project) async {
        await viewModel.launch(project)
        if viewModel.errorMessage == nil {
            NotificationCenter.default.post(name: .popoverShouldClose, object: nil)
        }
    }
}

private struct KeyboardShortcutCaptureView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyCaptureNSView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}
