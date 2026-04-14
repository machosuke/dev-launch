import SwiftUI

struct ProjectRowView: View {
    let project: Project
    let isLaunching: Bool
    let isSelected: Bool
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(project.name)
        .accessibilityHint("Opens \(project.name) in the configured editor")
    }
}
