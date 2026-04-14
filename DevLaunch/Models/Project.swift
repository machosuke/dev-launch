import Foundation

struct Project: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let path: String
    var lastLaunchedAt: Date?

    init(path: String, lastLaunchedAt: Date? = nil) {
        self.id = UUID()
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.path = path
        self.lastLaunchedAt = lastLaunchedAt
    }
}
