import Foundation
import XCTest
@testable import RunOverlayCore

final class ProjectResourceStatusTests: XCTestCase {
    func test移除异常视频立即清除视频状态而保留真实运动文件异常() {
        let missingVideo = makeVideo(name: "缺失.mp4", path: "/tmp/缺失.mp4")
        let keptVideo = makeVideo(name: "保留.mp4", path: "/tmp/保留.mp4")
        var project = RunOverlayProject(
            activitySource: activitySource(),
            videos: [missingVideo, keptVideo]
        )

        func status(_ project: RunOverlayProject, activityReadable: Bool) ->
            ProjectResourceStatus {
            ProjectResourceStatus(
                project: project,
                videoURL: { $0.fileURL },
                timeResourceURL: { $0.fileURL },
                activityURL: { $0.fileURL },
                isReadable: { url in
                    url.lastPathComponent == "保留.mp4" ||
                        (activityReadable && url.pathExtension == "fit")
                }
            )
        }

        let before = status(project, activityReadable: false)
        XCTAssertEqual(before.missingVideoIDs, [missingVideo.id])
        XCTAssertTrue(before.isActivitySourceMissing)

        project.videos.removeAll { $0.id == missingVideo.id }
        let after = status(project, activityReadable: false)
        XCTAssertTrue(after.missingVideoIDs.isEmpty)
        XCTAssertEqual(project.videos.map(\.id), [keptVideo.id])
        XCTAssertTrue(after.isActivitySourceMissing, "删除视频不应掩盖仍缺失的 FIT")

        let restoredActivity = status(project, activityReadable: true)
        XCTAssertFalse(restoredActivity.isActivitySourceMissing)
        XCTAssertTrue(restoredActivity.missingVideoIDs.isEmpty)
    }

    func test清空视频后仅独立检查运动数据并支持撤销后的重新计算() {
        let video = makeVideo(name: "片段.mp4", path: "/tmp/片段.mp4")
        var project = RunOverlayProject(
            activitySource: activitySource(),
            videos: [video]
        )
        let original = project
        project.videos.removeAll()

        func status(_ project: RunOverlayProject) -> ProjectResourceStatus {
            ProjectResourceStatus(
                project: project,
                videoURL: { $0.fileURL },
                timeResourceURL: { $0.fileURL },
                activityURL: { $0.fileURL },
                isReadable: { $0.pathExtension == "fit" }
            )
        }

        XCTAssertTrue(status(project).missingVideoIDs.isEmpty)
        XCTAssertTrue(status(project).missingTimeResourceVideoIDs.isEmpty)
        XCTAssertFalse(status(project).isActivitySourceMissing)

        project = original
        XCTAssertEqual(status(project).missingVideoIDs, [video.id])
    }

    private func makeVideo(name: String, path: String) -> VideoItem {
        VideoItem(
            fileName: name,
            fileURL: URL(fileURLWithPath: path),
            metadata: VideoAssetMetadata(
                durationSeconds: 10,
                dimensions: PixelDimensions(width: 1_920, height: 1_080),
                frameRate: 30,
                capturedAt: nil,
                hasAudio: false,
                container: "mp4",
                fileSizeBytes: 1_000
            )
        )
    }

    private func activitySource() -> ActivitySource {
        ActivitySource(
            fileName: "跑步.fit",
            fileURL: URL(fileURLWithPath: "/tmp/跑步.fit"),
            kind: .fit
        )
    }
}
