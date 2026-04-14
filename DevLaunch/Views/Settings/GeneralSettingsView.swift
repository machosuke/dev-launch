import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(AppStorageKey.scanFolderPath) private var scanFolderPath: String = ""
    @AppStorage(AppStorageKey.sortOrder) private var sortOrderRaw: String = SortOrder.recentFirst.rawValue
    @StateObject private var loginItemManager = LoginItemManager()

    private var sortOrderBinding: Binding<SortOrder> {
        Binding(
            get: { SortOrder(rawValue: sortOrderRaw) ?? .recentFirst },
            set: { sortOrderRaw = $0.rawValue }
        )
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { loginItemManager.isEnabled },
            set: { loginItemManager.setEnabled($0) }
        )
    }

    var body: some View {
        Form {
            Section("Projects") {
                LabeledContent("Scan Folder") {
                    HStack(spacing: 8) {
                        Text(folderDisplayName)
                            .foregroundStyle(scanFolderPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 200, alignment: .trailing)
                        Button("Choose…") { selectFolder() }
                    }
                }

                Picker("Sort Order", selection: sortOrderBinding) {
                    Text("Recent First").tag(SortOrder.recentFirst)
                    Text("Alphabetical").tag(SortOrder.alphabetical)
                }
                .pickerStyle(.radioGroup)
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: loginItemBinding)
            }
        }
        .formStyle(.grouped)
    }

    private var folderDisplayName: String {
        if scanFolderPath.isEmpty { return "Not set" }
        return URL(fileURLWithPath: scanFolderPath).lastPathComponent
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to scan for Git projects"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scanFolderPath = url.path
        NotificationCenter.default.post(name: .scanFolderDidChange, object: url)
    }
}
