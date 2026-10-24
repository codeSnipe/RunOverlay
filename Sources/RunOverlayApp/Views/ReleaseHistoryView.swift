import RunOverlayCore
import SwiftUI

struct ReleaseHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    private let bundle: Bundle = .main

    private var baseVersion: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.0"
    }

    private var currentVersion: String {
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "1"
        guard build.count == 3 else {
            return "\(baseVersion) (\(AppStrings.text("ui.release.development")))"
        }
        return "\(baseVersion)-\(build)"
    }

    private var currentRelease: ReleaseNote? {
        ReleaseHistory.note(forVersion: currentVersion, base: baseVersion)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(EditorTheme.accent)
                    .frame(width: 46, height: 46)
                    .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(AppStrings.text("ui.release.title"))
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(EditorTheme.text)
                    Text(AppStrings.format("ui.release.currentVersion", currentVersion))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EditorTheme.muted)
                }
                Spacer()
                Button(AppStrings.text("ui.release.close")) {
                    dismiss()
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
            }
            .padding(24)

            EditorTheme.separator.frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if currentRelease == nil {
                        releaseCard(
                            version: AppStrings.text("ui.release.development"),
                            date: nil,
                            title: AppStrings.text("ui.release.developmentTitle"),
                            changes: ReleaseHistory.developmentChangeKeys,
                            isCurrent: true
                        )
                    }

                    ForEach(ReleaseHistory.published) { note in
                        releaseCard(
                            version: note.version(base: baseVersion),
                            date: note.date,
                            title: AppStrings.text(note.titleKey),
                            changes: note.changeKeys,
                            isCurrent: currentRelease?.id == note.id
                        )
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(EditorTheme.canvas)
        }
        .frame(minWidth: 570, minHeight: 480)
        .background(EditorTheme.sidebar)
    }

    private func releaseCard(
        version: String,
        date: String?,
        title: String,
        changes: [String],
        isCurrent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(version)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EditorTheme.text)
                if isCurrent {
                    Text(AppStrings.text("ui.release.current"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(EditorTheme.canvas)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(EditorTheme.accent, in: Capsule())
                }
                Spacer()
                if let date {
                    Text(date)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(EditorTheme.muted)
                }
            }

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(EditorTheme.text)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(changes, id: \.self) { key in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(EditorTheme.accent)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(AppStrings.text(key))
                            .font(.system(size: 12))
                            .foregroundStyle(EditorTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 13))
    }
}
