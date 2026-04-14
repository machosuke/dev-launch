import SwiftUI

struct ProjectListView: View {
    @ObservedObject var viewModel: ProjectListViewModel

    var body: some View {
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
            } else if viewModel.projects.isEmpty {
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
                        ForEach(viewModel.projects) { project in
                            ProjectRowView(
                                project: project,
                                isLaunching: viewModel.isLaunching
                            ) {
                                Task { await viewModel.launch(project) }
                            }

                            if project.id != viewModel.projects.last?.id {
                                Divider()
                                    .padding(.leading, 38)
                            }
                        }
                    }
                    .padding(.vertical, 4)
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
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
        .task {
            if viewModel.hasScanFolder {
                await viewModel.performScan()
            }
        }
    }
}
