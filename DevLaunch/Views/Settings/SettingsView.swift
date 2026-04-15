import SwiftUI

enum SettingsTab: Int, CaseIterable {
    case general, editor, shortcut

    var label: String {
        switch self {
        case .general: return "General"
        case .editor: return "Editor"
        case .shortcut: return "Shortcut"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .editor: return "keyboard"
        case .shortcut: return "command"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.label, systemImage: tab.icon)
                            .font(.system(size: 12))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                selectedTab == tab
                                    ? Capsule().fill(Color.accentColor)
                                    : Capsule().fill(Color.clear)
                            )
                            .foregroundColor(selectedTab == tab ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 12)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .editor:
                    EditorSettingsView()
                case .shortcut:
                    ShortcutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 420, height: 340)
    }
}
