import Foundation

enum AICliPreset: String, CaseIterable, Identifiable {
    case claudeCode = "claude"
    case codex      = "codex"
    case custom     = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex CLI"
        case .custom:     return "Custom…"
        }
    }

    var command: String? {
        switch self {
        case .custom: return nil
        default: return rawValue
        }
    }

    static func from(command: String) -> AICliPreset {
        allCases.first { $0.command == command } ?? .custom
    }
}
