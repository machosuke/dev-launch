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

            if viewModel.hasScanFolder && !viewModel.scanner.isScanning {
                SearchField(
                    text: $viewModel.searchText,
                    onArrowUp: { moveSelection(by: -1, in: viewModel.projects) },
                    onArrowDown: { moveSelection(by: 1, in: viewModel.projects) },
                    onReturn: {
                        if let project = selectedProject(in: viewModel.projects) {
                            Task { await launch(project) }
                        }
                    },
                    onEscape: {
                        if !viewModel.searchText.isEmpty {
                            viewModel.searchText = ""
                        } else {
                            NotificationCenter.default.post(name: .popoverShouldClose, object: nil)
                        }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

                Divider()
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
            } else if projects.isEmpty && !viewModel.searchText.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No matching projects")
                        .font(.headline)
                    Text("No projects match \"\(viewModel.searchText)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
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
        .onAppear {
            syncSelection(with: projects)
        }
        .onChange(of: projects) { newProjects in
            syncSelection(with: newProjects)
        }
        .onChange(of: viewModel.searchText) { _ in
            syncSelection(with: viewModel.projects)
        }
        .task {
            if viewModel.hasScanFolder {
                await viewModel.performScan()
            }
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
