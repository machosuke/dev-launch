import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

            EditorSettingsView()
                .tabItem {
                    Label("Editor", systemImage: "keyboard")
                }
                .tag(1)

            ShortcutSettingsView()
                .tabItem {
                    Label("Shortcut", systemImage: "command")
                }
                .tag(2)
        }
        .frame(width: 420, height: 340)
    }
}
