import Foundation

enum EditorPreset: String, CaseIterable, Identifiable {
    case vsCode = "code"
    case cursor = "cursor"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vsCode: return "VS Code"
        case .cursor: return "Cursor"
        case .custom: return "Custom…"
        }
    }

    var command: String? {
        switch self {
        case .custom: return nil
        default: return rawValue
        }
    }

    static func from(command: String) -> EditorPreset {
        allCases.first { $0.command == command } ?? .custom
    }
}
