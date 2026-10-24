import Foundation
import CoreGraphics

/// 导出弹窗的展示状态与后台任务的运行状态分开处理。
public enum ExportQueueInteractionPolicy {
    public static func canBrowseVideos(
        batchRunning: Bool,
        queuePresented: Bool
    ) -> Bool {
        !batchRunning || !queuePresented
    }

    public static func shouldRetainFinishedResults(
        queuePresented: Bool,
        hasFailures: Bool
    ) -> Bool {
        queuePresented || hasFailures
    }
}

public struct ExportVideoSelection: Sendable {
    public init() {}

    public func videos(
        from projectVideos: [VideoItem],
        selectedIDs: Set<UUID>
    ) -> [VideoItem] {
        projectVideos.filter { selectedIDs.contains($0.id) }
    }

    /// 导出勾选不应成为编辑区长期多选；只高亮当前预览的视频。
    public func selectionAfterExport(
        from projectVideos: [VideoItem],
        currentID: UUID?
    ) -> Set<UUID>? {
        guard let currentID,
              projectVideos.contains(where: { $0.id == currentID }) else {
            return nil
        }
        return [currentID]
    }

    public func videoIDs(
        intersecting selection: CGRect,
        rowFrames: [UUID: CGRect]
    ) -> Set<UUID> {
        Set(rowFrames.compactMap { id, frame in
            frame.intersects(selection) ? id : nil
        })
    }
}
