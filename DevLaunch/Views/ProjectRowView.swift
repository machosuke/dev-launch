import SwiftUI

struct ProjectRowView: View {
    let project: Project
    let isLaunching: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(project.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if isLaunching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
