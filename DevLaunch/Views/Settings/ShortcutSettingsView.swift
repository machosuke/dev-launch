import SwiftUI
import Carbon

struct ShortcutSettingsView: View {
    @AppStorage(AppStorageKey.globalShortcutKeyCode) private var keyCode: Int = -1
    @AppStorage(AppStorageKey.globalShortcutModifiers) private var modifiers: Int = 0
    @State private var isRecording: Bool = false
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()

    private var currentShortcut: GlobalShortcut {
        GlobalShortcut(keyCode: keyCode, modifiers: UInt64(max(0, modifiers)))
    }

    var body: some View {
        Form {
            Section("Global Shortcut") {
                LabeledContent("Toggle DevLaunch") {
                    HStack(spacing: 8) {
                        ShortcutRecorderView(
                            shortcut: currentShortcut,
                            isRecording: $isRecording
                        ) { newShortcut in
                            keyCode = newShortcut.keyCode
                            modifiers = Int(newShortcut.modifiers)
                            isRecording = false
                            NotificationCenter.default.post(name: .shortcutDidChange, object: nil)
                        }
                        .frame(width: 140, height: 24)

                        if currentShortcut.isSet {
                            Button("Clear") {
                                keyCode = -1
                                modifiers = 0
                                isRecording = false
                                NotificationCenter.default.post(name: .shortcutDidChange, object: nil)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        }
                    }
                }

                Text("Press the shortcut while DevLaunch is running to show/hide the project list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !accessibilityGranted {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Accessibility Permission Required")
                                .font(.body.bold())
                            Text("Global shortcuts require Accessibility access in System Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Open System Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
        }
    }
}

// MARK: - ShortcutRecorderView

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: GlobalShortcut
    @Binding var isRecording: Bool
    let onRecord: (GlobalShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onRecord = onRecord
        view.onStartRecording = { isRecording = true }
        view.onCancelRecording = { isRecording = false }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.currentShortcut = shortcut
        nsView.isRecording = isRecording
        nsView.needsDisplay = true
    }
}

final class ShortcutRecorderNSView: NSView {
    var currentShortcut: GlobalShortcut = .none
    var isRecording: Bool = false
    var onRecord: ((GlobalShortcut) -> Void)?
    var onStartRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var focusRingType: NSFocusRingType {
        get { .exterior }
        set { }
    }

    // MARK: - Accessibility

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Global Shortcut" }
    override func accessibilityValue() -> Any? {
        currentShortcut.isSet ? currentShortcut.displayString : "Not set"
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        if !isRecording {
            window?.makeFirstResponder(self)
            isRecording = true
            onStartRecording?()
            needsDisplay = true
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        onStartRecording?()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            // Space or Return starts recording
            if event.keyCode == 49 || event.keyCode == 36 {
                window?.makeFirstResponder(self)
                isRecording = true
                onStartRecording?()
                needsDisplay = true
                return
            }
            super.keyDown(with: event)
            return
        }

        // Esc cancels recording
        if event.keyCode == 53 {
            isRecording = false
            onCancelRecording?()
            needsDisplay = true
            return
        }

        // Require at least one modifier (Cmd, Ctrl, or Opt)
        let mods = event.modifierFlags.intersection([.command, .option, .control])
        guard !mods.isEmpty else { return }

        // Convert NSEvent modifierFlags to CGEventFlags
        var cgFlags: UInt64 = 0
        if event.modifierFlags.contains(.control) { cgFlags |= CGEventFlags.maskControl.rawValue }
        if event.modifierFlags.contains(.option)  { cgFlags |= CGEventFlags.maskAlternate.rawValue }
        if event.modifierFlags.contains(.shift)   { cgFlags |= CGEventFlags.maskShift.rawValue }
        if event.modifierFlags.contains(.command) { cgFlags |= CGEventFlags.maskCommand.rawValue }

        let newShortcut = GlobalShortcut(keyCode: Int(event.keyCode), modifiers: cgFlags)
        isRecording = false
        onRecord?(newShortcut)
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            onCancelRecording?()
            needsDisplay = true
        }
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        // Background
        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.1).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()

        // Border
        if isRecording {
            NSColor.controlAccentColor.setStroke()
        } else {
            NSColor.separatorColor.setStroke()
        }
        path.lineWidth = 1
        path.stroke()

        // Label text
        let text: String
        if isRecording {
            text = "Recording…"
        } else if currentShortcut.isSet {
            text = currentShortcut.displayString
        } else {
            text = "Click to record"
        }

        let foregroundColor: NSColor
        if isRecording {
            foregroundColor = .controlAccentColor
        } else if currentShortcut.isSet {
            foregroundColor = .labelColor
        } else {
            foregroundColor = .secondaryLabelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: isRecording ? .medium : .regular),
            .foregroundColor: foregroundColor,
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.size()
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attrString.draw(in: textRect)
    }
}
