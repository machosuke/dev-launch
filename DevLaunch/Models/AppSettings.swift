import Carbon
import CoreGraphics
import Foundation

// MARK: - GlobalShortcut

struct GlobalShortcut: Equatable {
    let keyCode: Int
    let modifiers: UInt64

    static let none = GlobalShortcut(keyCode: -1, modifiers: 0)

    var isSet: Bool { keyCode >= 0 }

    var displayString: String {
        guard isSet else { return "None" }

        var result = ""

        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl)   { result += "⌃" }
        if flags.contains(.maskAlternate) { result += "⌥" }
        if flags.contains(.maskShift)     { result += "⇧" }
        if flags.contains(.maskCommand)   { result += "⌘" }

        result += keyDisplayName(for: keyCode)
        return result
    }

    // MARK: - Private

    private func keyDisplayName(for code: Int) -> String {
        switch code {
        // Letters (kVK_ANSI_A = 0 … kVK_ANSI_Z scattered in Carbon)
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_M: return "M"

        // Number row
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_0: return "0"

        // Special keys
        case kVK_Space:     return "Space"
        case kVK_Return:    return "↩"
        case kVK_Tab:       return "⇥"
        case kVK_Delete:    return "⌫"
        case kVK_Escape:    return "⎋"

        // Function keys
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"

        // Arrow keys
        case kVK_LeftArrow:  return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow:  return "↓"
        case kVK_UpArrow:    return "↑"

        default: return "(\(code))"
        }
    }
}

// MARK: - AppDefaults

enum AppDefaults {
    static let editorCommand = "code"
    static let aiCliCommand = "claude"
    static let aiCliOptions = ""
    static let usesIntegratedTerminal = true
    static let sortOrder = "recentFirst"
    static let launchAtLogin = false
    static let globalShortcutKeyCode = -1
    static let globalShortcutModifiers: UInt64 = 0
}

// MARK: - Notification Names

extension Notification.Name {
    static let scanFolderDidChange = Notification.Name("com.machosuke.DevLaunch.scanFolderDidChange")
    static let shortcutDidChange   = Notification.Name("com.machosuke.DevLaunch.shortcutDidChange")
}
