import Foundation

struct Project: Identifiable, Equatable, Hashable {
    let name: String
    let path: String
    var lastLaunchedAt: Date?

    // path を ID にすることで、再スキャン後も同一プロジェクトの View 識別性を保つ
    var id: String { path }

    init(path: String, lastLaunchedAt: Date? = nil) {
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.path = path
        self.lastLaunchedAt = lastLaunchedAt
    }
}
