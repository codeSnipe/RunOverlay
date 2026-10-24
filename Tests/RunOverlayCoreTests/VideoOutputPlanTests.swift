import Foundation
import XCTest
@testable import RunOverlayCore

final class VideoOutputPlanTests: XCTestCase {
    func test横屏切竖屏先提醒黑边旋转后匹配() {
        var video = makeVideo()
        let defaults = ExportSettings(
            maximumHeight: 1_080,
            aspectRatio: .portrait9x16
        )

        let unrotated = VideoOutputPlan(video: video, defaults: defaults)
        XCTAssertEqual(unrotated.outputDimensions, PixelDimensions(
            width: 1_080, height: 1_920
        ))
        XCTAssertTrue(unrotated.hasLetterboxing)
        XCTAssertFalse(unrotated.needsUpscaling)

        video.rotation = .clockwise90
        let rotated = VideoOutputPlan(video: video, defaults: defaults)
        XCTAssertEqual(rotated.rotatedDimensions, PixelDimensions(
            width: 1_080, height: 1_920
        ))
        XCTAssertEqual(rotated.outputDimensions, PixelDimensions(
            width: 1_080, height: 1_920
        ))
        XCTAssertFalse(rotated.hasLetterboxing)
        XCTAssertFalse(rotated.needsUpscaling)

        video.rotation = video.rotation.rotated(clockwise: true)
        XCTAssertEqual(video.rotation, .halfTurn)
        XCTAssertTrue(VideoOutputPlan(video: video, defaults: defaults).needsAttention)
        video.rotation = video.rotation.rotated(clockwise: false)
        XCTAssertEqual(video.rotation, .clockwise90)
        video.rotation = video.rotation.rotated(clockwise: false)
        XCTAssertEqual(video.rotation, .none)
        video.rotation = video.rotation.rotated(clockwise: false)
        XCTAssertEqual(video.rotation, .counterclockwise90)
        XCTAssertFalse(VideoOutputPlan(video: video, defaults: defaults).hasLetterboxing)
        video.rotation = video.rotation.rotated(clockwise: true)
        XCTAssertEqual(video.rotation, .none)
    }

    func test统一画幅下不同素材像素尺寸不误报() {
        var video = makeVideo()
        let defaults = ExportSettings(
            maximumHeight: 720,
            aspectRatio: .landscape16x9
        )
        XCTAssertEqual(
            VideoOutputPlan(video: video, defaults: defaults).outputDimensions,
            PixelDimensions(width: 1_280, height: 720)
        )
        video.metadata.dimensions = PixelDimensions(width: 2_688, height: 1_512)
        XCTAssertFalse(VideoOutputPlan(video: video, defaults: defaults).needsAttention)
        video.exportMaximumHeight = 2_160
        video.exportAspectRatio = .portrait9x16
        let plan = VideoOutputPlan(video: video, defaults: defaults)
        XCTAssertEqual(plan.outputDimensions, PixelDimensions(width: 1_280, height: 720))
        XCTAssertFalse(plan.hasLetterboxing)
        XCTAssertFalse(plan.needsAttention)
    }

    func test列表目标比例不符告警且可旋转消除() {
        var video = makeVideo()
        let fullHD = ExportSettings(
            maximumHeight: 1_080,
            aspectRatio: .landscape16x9
        )
        XCTAssertFalse(VideoOutputPlan(video: video, defaults: fullHD).needsAttention)

        video.metadata.dimensions = PixelDimensions(width: 2_688, height: 1_512)
        let mismatched = VideoOutputPlan(video: video, defaults: fullHD)
        XCTAssertFalse(mismatched.needsAttention)

        let original = ExportSettings(aspectRatio: .source)
        let originalPlan = VideoOutputPlan(video: video, defaults: original)
        XCTAssertFalse(originalPlan.needsAttention)

        let portrait = ExportSettings(
            maximumHeight: 1_080,
            aspectRatio: .portrait9x16
        )
        XCTAssertTrue(VideoOutputPlan(video: video, defaults: portrait).needsAttention)
        video.rotation = .clockwise90
        XCTAssertFalse(VideoOutputPlan(video: video, defaults: portrait).needsAttention)
        video.exportAspectRatio = .landscape16x9
        video.exportMaximumHeight = 720
        XCTAssertFalse(VideoOutputPlan(video: video, defaults: portrait).needsAttention)
    }

    func test统一比例随项目保存并可恢复() throws {
        var project = RunOverlayProject(videos: [makeVideo()])
        project.exportSettings.aspectRatio = .portrait9x16
        let restored = try ProjectFileCodec().decode(
            ProjectFileCodec().encode(project)
        )
        XCTAssertEqual(restored.exportSettings.aspectRatio, .portrait9x16)
        let plan = VideoOutputPlan(
            video: try XCTUnwrap(restored.videos.first),
            defaults: restored.exportSettings
        )
        XCTAssertEqual(plan.aspectRatio, .portrait9x16)
        XCTAssertTrue(plan.needsAttention)
    }

    func test单视频设置可保存且旧文件缺少字段时沿用默认() throws {
        var project = RunOverlayProject(videos: [makeVideo()])
        project.videos[0].rotation = .clockwise90
        project.videos[0].exportAspectRatio = .portrait9x16
        project.videos[0].exportMaximumHeight = 720
        let codec = ProjectFileCodec()
        let restored = try codec.decode(codec.encode(project))
        XCTAssertEqual(restored.videos[0].rotation, .clockwise90)
        XCTAssertEqual(restored.videos[0].exportAspectRatio, .portrait9x16)
        XCTAssertEqual(restored.videos[0].exportMaximumHeight, 720)
        XCTAssertEqual(restored.overlay, project.overlay)

        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: codec.encode(project)) as? [String: Any]
        )
        var videos = try XCTUnwrap(json["videos"] as? [[String: Any]])
        videos[0].removeValue(forKey: "rotation")
        videos[0].removeValue(forKey: "exportAspectRatio")
        videos[0].removeValue(forKey: "exportMaximumHeight")
        json["videos"] = videos
        let legacy = try codec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.videos[0].rotation, .none)
        XCTAssertNil(legacy.videos[0].exportAspectRatio)
        XCTAssertNil(legacy.videos[0].exportMaximumHeight)
    }

    private func makeVideo() -> VideoItem {
        VideoItem(
            fileName: "跑步.mov",
            fileURL: URL(fileURLWithPath: "/tmp/跑步.mov"),
            metadata: VideoAssetMetadata(
                durationSeconds: 60,
                dimensions: PixelDimensions(width: 1_920, height: 1_080),
                frameRate: 30,
                capturedAt: nil,
                hasAudio: true,
                container: "MOV",
                fileSizeBytes: 10_000
            )
        )
    }
}
