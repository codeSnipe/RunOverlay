import RunOverlayCore
import SwiftUI

struct ExportQueueView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVideoIDs: Set<UUID> = []
    @State private var isShowingOutputWarning = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(EditorTheme.separator)
                .frame(height: 1)

            if appModel.exportJobs.isEmpty {
                preparation
            } else {
                List(appModel.exportJobs) { job in
                    ExportJobRow(
                        job: job,
                        thumbnail: appModel.videoThumbnails[job.videoID],
                        onCancel: { appModel.cancelExport(job.id) },
                        onRetry: { appModel.retryExport(job.id) },
                        onReveal: { appModel.revealExport(job.id) }
                    )
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(EditorTheme.inspector)
            }

            Rectangle()
                .fill(EditorTheme.separator)
                .frame(height: 1)
            footer
        }
        .background(EditorTheme.sidebar)
        .onAppear {
            if appModel.exportJobs.isEmpty {
                selectedVideoIDs = appModel.videosSelectedForExport
            }
        }
        .onChange(of: appModel.project.videos.map(\.id)) { _, videoIDs in
            selectedVideoIDs.formIntersection(Set(videoIDs))
        }
        .confirmationDialog(
            AppStrings.text("ui.export.outputWarningTitle"),
            isPresented: $isShowingOutputWarning,
            titleVisibility: .visible
        ) {
            Button(AppStrings.text("ui.export.continueWithOutputWarnings")) {
                appModel.enqueueVideos(selectedIDs: selectedVideoIDs)
            }
            Button(AppStrings.text("ui.common.cancel"), role: .cancel) {}
        } message: {
            Text(AppStrings.format("ui.export.outputWarningSummary", problematicVideos.count))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.text("ui.export.title"))
                        .font(.title2.bold())
                    if !appModel.exportJobs.isEmpty {
                        Text(
                            AppStrings.text(
                                appModel.exportBatchIsFinished
                                    ? (appModel.exportBatchUnsuccessfulCount > 0
                                        ? "ui.export.finishedWithErrors"
                                        : "ui.export.finished")
                                    : "ui.export.exporting"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(
                            AppStrings.format(
                                "ui.export.completedCount",
                                appModel.exportBatchCompletedCount,
                                appModel.exportJobs.count
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(
                            AppStrings.format(
                                "ui.export.readyCount",
                                selectedVideoIDs.count
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let directory = appModel.exportDirectoryDisplayName {
                        Label(directory, systemImage: "folder")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    appModel.chooseExportDirectory()
                } label: {
                    Label(
                        AppStrings.text(
                            appModel.exportDirectoryDisplayName == nil
                                ? "ui.export.chooseFolder"
                                : "ui.export.changeFolder"
                        ),
                        systemImage: "folder"
                    )
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                .disabled(appModel.exportBatchHasStarted)

                if appModel.exportBatchHasStarted {
                    Button {
                        appModel.cancelAllExports()
                    } label: {
                        Label(AppStrings.text("ui.export.cancelAll"), systemImage: "xmark")
                    }
                    .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                    .disabled(!appModel.isExporting)

                    if !appModel.isExporting,
                       appModel.exportJobs.contains(where: { $0.status == .waiting }) {
                        Button {
                            appModel.resumeWaitingExports()
                        } label: {
                            Label(AppStrings.text("ui.export.resume"), systemImage: "play.fill")
                        }
                        .buttonStyle(EditorActionButtonStyle(tone: .primary, size: .compact))
                    }
                }
            }

            if !appModel.exportJobs.isEmpty {
                ProgressView(value: appModel.exportBatchProgress)
                    .tint(EditorTheme.accent)
                Text(
                    AppStrings.format(
                        "ui.export.progressPercent",
                        Int((appModel.exportBatchProgress * 100).rounded())
                    )
                )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
    }

    private var preparation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                AppStrings.text(
                    appModel.exportDirectoryDisplayName == nil
                        ? "ui.export.chooseFolderHint"
                        : "ui.export.readyDescription"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.top, 14)

            HStack {
                Text(AppStrings.text("ui.export.selectVideos"))
                    .font(.headline)
                Spacer()
                Button(AppStrings.text("ui.export.selectAll")) {
                    selectedVideoIDs = Set(appModel.project.videos.map(\.id))
                    appModel.setExportVideoSelection(selectedVideoIDs, previewIfSingle: false)
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                .disabled(selectedVideoIDs.count == appModel.project.videos.count)

                Button(AppStrings.text("ui.export.deselectAll")) {
                    selectedVideoIDs.removeAll()
                    appModel.setExportVideoSelection([], previewIfSingle: false)
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .compact))
                .disabled(selectedVideoIDs.isEmpty)
            }
            .padding(.horizontal, 18)

            if !problematicVideos.isEmpty {
                Label {
                    Text(AppStrings.format(
                        "ui.export.outputWarningSummary",
                        problematicVideos.count
                    ))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.yellow)
                .padding(.horizontal, 18)
            }

            List(appModel.project.videos) { video in
                Toggle(
                    isOn: Binding(
                        get: { selectedVideoIDs.contains(video.id) },
                        set: { isSelected in
                            if isSelected {
                                selectedVideoIDs.insert(video.id)
                            } else {
                                selectedVideoIDs.remove(video.id)
                            }
                            appModel.setExportVideoSelection(
                                selectedVideoIDs,
                                previewIfSingle: false
                            )
                        }
                    )
                ) {
                    HStack(spacing: 12) {
                        ExportVideoThumbnail(image: appModel.videoThumbnails[video.id])
                        VStack(alignment: .leading, spacing: 4) {
                            Text(video.fileName)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(
                                "\(RunOverlayFormatters.duration(video.metadata.durationSeconds)) · " +
                                    video.metadata.dimensions.displayText
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            let plan = appModel.outputPlan(for: video)
                            Text(AppStrings.format(
                                "ui.export.outputDescription",
                                plan.outputDimensions.displayText,
                                plan.rotation.rawValue
                            ))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            if plan.needsAttention {
                                Label(
                                    appModel.outputWarningDescription(for: plan),
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .toggleStyle(.checkbox)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(EditorTheme.inspector)
        }
    }

    private var problematicVideos: [VideoItem] {
        appModel.project.videos.filter {
            guard selectedVideoIDs.contains($0.id) else { return false }
            let plan = appModel.outputPlan(for: $0)
            return plan.needsAttention
        }
    }

    private var footer: some View {
        HStack {
            Text(
                AppStrings.format(
                    "ui.export.parallelCapacity",
                    appModel.project.exportSettings.parallelTaskCount
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if appModel.exportJobs.isEmpty {
                Button(AppStrings.text("ui.common.cancel")) {
                    appModel.dismissExportQueue()
                    dismiss()
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline))
                Button(AppStrings.text("ui.export.start")) {
                    if problematicVideos.isEmpty {
                        appModel.enqueueVideos(selectedIDs: selectedVideoIDs)
                    } else {
                        isShowingOutputWarning = true
                    }
                }
                .buttonStyle(EditorActionButtonStyle(tone: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(
                    appModel.exportDirectoryDisplayName == nil ||
                        selectedVideoIDs.isEmpty
                )
            } else if appModel.exportBatchIsFinished {
                Button(AppStrings.text("ui.export.done")) {
                    appModel.finishExportBatch()
                    dismiss()
                }
                .buttonStyle(EditorActionButtonStyle(tone: .primary))
                .keyboardShortcut(.defaultAction)
            } else {
                Button(AppStrings.text("ui.export.continueInBackground")) {
                    appModel.dismissExportQueue()
                    dismiss()
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline))
            }
        }
        .padding(16)
    }
}

private struct ExportJobRow: View {
    let job: ExportJob
    let thumbnail: NSImage?
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.status.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 24)

            ExportVideoThumbnail(image: thumbnail)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(job.fileName)
                        .lineLimit(1)
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    Text(job.status.displayName)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }

                if job.status == .exporting || job.status == .waiting {
                    ProgressView(value: job.progress)
                        .controlSize(.small)
                }

                if case let .failed(message) = job.status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    Text(job.outputURL.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            switch job.status {
            case .waiting, .exporting:
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .icon))
                .help(AppStrings.text("ui.export.cancelJob"))
            case .failed:
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .icon))
                .help(AppStrings.text("ui.export.retry"))
            case .completed:
                Button(action: onReveal) {
                    Image(systemName: "folder")
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline, size: .icon))
                .help(AppStrings.text("ui.export.reveal"))
            case .cancelled:
                EmptyView()
            }
        }
        .padding(.vertical, 5)
    }

    private var statusColor: Color {
        switch job.status {
        case .waiting: .secondary
        case .exporting: .accentColor
        case .completed: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }
}

private struct ExportVideoThumbnail: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film")
                    .font(.system(size: 19))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(width: 72, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}
