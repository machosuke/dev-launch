import SwiftUI

struct EditorSettingsView: View {
    @AppStorage(AppStorageKey.editorCommand) private var editorCommand: String = "code"
    @AppStorage(AppStorageKey.aiCliCommand) private var aiCliCommand: String = "claude"
    @AppStorage(AppStorageKey.aiCliOptions) private var aiCliOptions: String = ""
    @AppStorage(AppStorageKey.usesIntegratedTerminal) private var usesIntegratedTerminal: Bool = true

    @State private var selectedEditorPreset: EditorPreset = .vsCode
    @State private var selectedAICliPreset: AICliPreset = .claudeCode

    var body: some View {
        Form {
            Section("Editor") {
                Picker("Editor", selection: $selectedEditorPreset) {
                    ForEach(EditorPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: selectedEditorPreset) { newValue in
                    if let cmd = newValue.command {
                        editorCommand = cmd
                    }
                }

                if selectedEditorPreset == .custom {
                    TextField("Command", text: $editorCommand, prompt: Text("e.g. code"))
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("AI CLI") {
                Picker("AI CLI", selection: $selectedAICliPreset) {
                    ForEach(AICliPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: selectedAICliPreset) { newValue in
                    if let cmd = newValue.command {
                        aiCliCommand = cmd
                    }
                }

                if selectedAICliPreset == .custom {
                    TextField("Command", text: $aiCliCommand, prompt: Text("e.g. claude"))
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Extra Options (flags only)", text: $aiCliOptions, prompt: Text("e.g. --dangerously-skip-permissions"))
                    .textFieldStyle(.roundedBorder)

                Text("Enter only options here. The selected AI CLI command is added automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Terminal") {
                Toggle("Use Editor's Integrated Terminal", isOn: $usesIntegratedTerminal)

                Text(usesIntegratedTerminal
                    ? "AI CLI launches in the editor's integrated terminal."
                    : "AI CLI launches in Terminal.app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectedEditorPreset = EditorPreset.from(command: editorCommand)
            selectedAICliPreset = AICliPreset.from(command: aiCliCommand)
        }
    }
}
