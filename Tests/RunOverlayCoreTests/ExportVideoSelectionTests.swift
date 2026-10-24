import Foundation
import XCTest
@testable import RunOverlayCore

final class ExportVideoSelectionTests: XCTestCase {
    private let selector = ExportVideoSelection()

    func test全选按项目列表顺序导出() {
        let videos = makeVideos()
        let selected = selector.videos(
            from: videos,
            selectedIDs: Set(videos.map(\.id))
        )

        XCTAssertEqual(selected.map(\.id), videos.map(\.id))
    }

    func test部分选择只生成被勾选视频并保持列表顺序() {
        let videos = makeVideos()
        let selected = selector.videos(
            from: videos,
            selectedIDs: [videos[2].id, videos[0].id, UUID()]
        )

        XCTAssertEqual(selected.map(\.id), [videos[0].id, videos[2].id])
        XCTAssertEqual(
            selected.map(\.metadata.fileSizeBytes),
            [videos[0].metadata.fileSizeBytes, videos[2].metadata.fileSizeBytes]
        )
    }

    func test全部取消选择不会生成任务() {
        XCTAssertTrue(
            selector.videos(from: makeVideos(), selectedIDs: []).isEmpty
        )
    }

    func test导出结束恢复当前视频单选且不保留批量勾选() {
        let videos = makeVideos()
        XCTAssertEqual(
            selector.selectionAfterExport(
                from: videos,
                currentID: videos[1].id
            ),
            [videos[1].id]
        )
        XCTAssertNil(selector.selectionAfterExport(from: videos, currentID: nil))
        XCTAssertNil(selector.selectionAfterExport(from: videos, currentID: UUID()))
        XCTAssertEqual(
            selector.videos(from: videos, selectedIDs: Set(videos.map(\.id)))
                .map(\.id),
            videos.map(\.id),
            "恢复编辑单选不能影响已排队的视频"
        )
    }

    func test后台继续保持运行时恢复浏览并保留顶部进度() {
        XCTAssertFalse(ExportQueueInteractionPolicy.canBrowseVideos(
            batchRunning: true,
            queuePresented: true
        ))
        XCTAssertTrue(ExportQueueInteractionPolicy.canBrowseVideos(
            batchRunning: true,
            queuePresented: false
        ))
        XCTAssertTrue(ExportQueueInteractionPolicy.canBrowseVideos(
            batchRunning: false,
            queuePresented: true
        ))
        XCTAssertFalse(ExportQueueInteractionPolicy.shouldRetainFinishedResults(
            queuePresented: false,
            hasFailures: false
        ))
        XCTAssertTrue(ExportQueueInteractionPolicy.shouldRetainFinishedResults(
            queuePresented: true,
            hasFailures: false
        ))
        XCTAssertTrue(ExportQueueInteractionPolicy.shouldRetainFinishedResults(
            queuePresented: false,
            hasFailures: true
        ))
    }

    func test框选只包含与选择矩形相交的视频行() {
        let videos = makeVideos()
        let frames: [UUID: CGRect] = [
            videos[0].id: CGRect(x: 0, y: 0, width: 200, height: 40),
            videos[1].id: CGRect(x: 0, y: 40, width: 200, height: 40),
            videos[2].id: CGRect(x: 0, y: 80, width: 200, height: 40)
        ]

        let selection = CGRect(x: 10, y: 30, width: 100, height: 60)
        XCTAssertEqual(
            selector.videoIDs(intersecting: selection, rowFrames: frames),
            Set(videos.map(\.id))
        )
        XCTAssertTrue(selector.videoIDs(
            intersecting: CGRect(x: 250, y: 0, width: 20, height: 120),
            rowFrames: frames
        ).isEmpty)

        let reverseSelection = CGRect(
            x: 110,
            y: 90,
            width: -100,
            height: -60
        ).standardized
        XCTAssertEqual(
            selector.videoIDs(intersecting: reverseSelection, rowFrames: frames),
            Set(videos.map(\.id))
        )
    }

    func test方向键在视频列表中逐项移动且不会越界() {
        let videos = makeVideos()
        let navigation = VideoListNavigation()
        XCTAssertEqual(
            navigation.adjacentVideoID(in: videos, currentID: videos[0].id, direction: 1),
            videos[1].id
        )
        XCTAssertEqual(
            navigation.adjacentVideoID(in: videos, currentID: videos[1].id, direction: -1),
            videos[0].id
        )
        XCTAssertNil(navigation.adjacentVideoID(
            in: videos, currentID: videos[0].id, direction: -1
        ))
        XCTAssertNil(navigation.adjacentVideoID(
            in: videos, currentID: videos[2].id, direction: 1
        ))
    }

    func test没有当前视频时上下键分别从首尾开始() {
        let videos = makeVideos()
        let navigation = VideoListNavigation()
        XCTAssertEqual(
            navigation.adjacentVideoID(in: videos, currentID: nil, direction: 1),
            videos[0].id
        )
        XCTAssertEqual(
            navigation.adjacentVideoID(in: videos, currentID: UUID(), direction: -1),
            videos[2].id
        )
        XCTAssertNil(navigation.adjacentVideoID(in: [], currentID: nil, direction: 1))
        XCTAssertNil(navigation.adjacentVideoID(
            in: videos, currentID: videos[1].id, direction: 0
        ))
    }

    private func makeVideos() -> [VideoItem] {
        (1...3).map { number in
            VideoItem(
                fileName: "VID_\(number).mp4",
                fileURL: URL(fileURLWithPath: "/tmp/VID_\(number).mp4"),
                metadata: VideoAssetMetadata(
                    durationSeconds: 10,
                    dimensions: PixelDimensions(width: 1_920, height: 1_080),
                    frameRate: 30,
                    capturedAt: nil,
                    hasAudio: false,
                    container: "mp4",
                    fileSizeBytes: Int64(number * 1_000)
                )
            )
        }
    }
}
