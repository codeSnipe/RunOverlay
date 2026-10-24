import Foundation
import XCTest
@testable import RunOverlayCore

final class ProjectPackageServiceTests: XCTestCase {
    func test封面原图与导出图片随项目打包并可重连() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("原素材", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        let videoURL = sourceDirectory.appendingPathComponent("跑步.mp4")
        let coverURL = sourceDirectory.appendingPathComponent("输入.png")
        let exportedURL = sourceDirectory.appendingPathComponent("封面.jpg")
        try Data("video".utf8).write(to: videoURL)
        try Data("original-cover".utf8).write(to: coverURL)
        try Data("exported-cover".utf8).write(to: exportedURL)

        let cover = VideoCover(
            source: .image(CoverImageResource(fileURL: coverURL)),
            textLayers: [
                CoverTextLayer(
                    text: "跑步",
                    depth: .behindSelectedPeople,
                    selectedPeople: [CoverPoint(x: 0.5, y: 0.5)]
                )
            ],
            exportedImage: CoverImageResource(fileURL: exportedURL)
        )
        let video = VideoItem(
            fileName: videoURL.lastPathComponent,
            fileURL: videoURL,
            metadata: VideoAssetMetadata(
                durationSeconds: 5,
                dimensions: PixelDimensions(width: 320, height: 180),
                frameRate: 30,
                capturedAt: nil,
                hasAudio: false,
                container: "MP4",
                fileSizeBytes: 5
            ),
            cover: cover
        )
        let packageURL = root.appendingPathComponent("封面项目.runoverlay-package")
        let result = try ProjectPackageService().packageProject(
            RunOverlayProject(videos: [video]),
            to: packageURL,
            resolveURL: { url, _ in url }
        )
        XCTAssertEqual(result.copiedFileCount, 3)
        XCTAssertTrue(result.missingFiles.isEmpty)

        let reloaded = try ProjectFileCodec().load(from: result.projectURL)
        let savedCover = try XCTUnwrap(reloaded.videos.first?.cover)
        XCTAssertEqual(savedCover.textLayers, cover.textLayers)
        let relocation = ResourceRelocator().resolveProjectResources(
            reloaded,
            relativeTo: packageURL
        )
        XCTAssertEqual(
            relocation.coverSourceURLs[video.id]?.lastPathComponent,
            coverURL.lastPathComponent
        )
        XCTAssertEqual(
            relocation.coverExportURLs[video.id]?.lastPathComponent,
            exportedURL.lastPathComponent
        )
        XCTAssertEqual(
            try Data(contentsOf: XCTUnwrap(relocation.coverSourceURLs[video.id])),
            Data("original-cover".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: XCTUnwrap(relocation.coverExportURLs[video.id])),
            Data("exported-cover".utf8)
        )
    }

    func test打包项目复制素材并使用包内路径重定位() throws {
        let root = try temporaryDirectory()
        let sourceDirectory = root.appendingPathComponent("原始素材")
        let packageDirectory = root.appendingPathComponent("导出包.runoverlay-package")
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )

        let videoURL = sourceDirectory.appendingPathComponent("跑步.mov")
        let timeResourceURL = sourceDirectory.appendingPathComponent("跑步.lrv")
        let activityURL = sourceDirectory.appendingPathComponent("活动.gpx")
        try Data("video-data".utf8).write(to: videoURL)
        try Data("sidecar-data".utf8).write(to: timeResourceURL)
        try Data("<gpx/>".utf8).write(to: activityURL)

        let project = RunOverlayProject(
            name: "周末跑步",
            activitySource: ActivitySource(
                fileName: activityURL.lastPathComponent,
                fileURL: activityURL,
                kind: .gpx,
                sampleCount: 0
            ),
            videos: [
                VideoItem(
                    fileName: videoURL.lastPathComponent,
                    fileURL: videoURL,
                    metadata: VideoAssetMetadata(
                        durationSeconds: 12,
                        dimensions: PixelDimensions(width: 1_920, height: 1_080),
                        frameRate: 30,
                        capturedAt: nil,
                        hasAudio: true,
                        container: "MOV",
                        fileSizeBytes: 10
                    ),
                    timeResource: VideoTimeResource(
                        fileName: timeResourceURL.lastPathComponent,
                        fileURL: timeResourceURL,
                        capturedAt: Date(timeIntervalSince1970: 42)
                    )
                )
            ]
        )

        let result = try ProjectPackageService().packageProject(
            project,
            to: packageDirectory,
            resolveURL: { url, _ in url }
        )

        XCTAssertEqual(result.copiedFileCount, 3)
        XCTAssertTrue(result.missingFiles.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.projectURL.path))

        let packagedProject = try ProjectFileCodec().load(from: result.projectURL)
        XCTAssertEqual(packagedProject.videos[0].resourceRelativePath, "素材/跑步.mov")
        XCTAssertEqual(
            packagedProject.videos[0].timeResource?.resourceRelativePath,
            "素材/时间资源/跑步.lrv"
        )
        XCTAssertEqual(packagedProject.activitySource?.resourceRelativePath, "素材/活动.gpx")

        let relocation = ResourceRelocator().resolveProjectResources(
            packagedProject,
            relativeTo: packageDirectory
        )
        XCTAssertEqual(
            relocation.videoURLs[packagedProject.videos[0].id]?.lastPathComponent,
            "跑步.mov"
        )
        XCTAssertEqual(
            relocation.sidecarURLs[packagedProject.videos[0].id]?.lastPathComponent,
            "跑步.lrv"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(
                    relocation.sidecarURLs[packagedProject.videos[0].id]
                ).path
            )
        )
        XCTAssertEqual(relocation.activityURL?.lastPathComponent, "活动.gpx")
        XCTAssertTrue(relocation.missingVideoIDs.isEmpty)

        try? FileManager.default.removeItem(at: root)
    }

    func test打包目标存在时拒绝覆盖() throws {
        let root = try temporaryDirectory()
        let packageDirectory = root.appendingPathComponent("现有项目")
        try FileManager.default.createDirectory(
            at: packageDirectory,
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(
            try ProjectPackageService().packageProject(
                RunOverlayProject(),
                to: packageDirectory,
                resolveURL: { url, _ in url }
            )
        ) { error in
            XCTAssertEqual(
                error as? ProjectPackageError,
                .destinationAlreadyExists
            )
        }
        try? FileManager.default.removeItem(at: root)
    }

    func test缺失素材会被打包结果标记且不生成错误引用() throws {
        let root = try temporaryDirectory()
        let missingURL = root.appendingPathComponent("不存在.mp4")
        let project = RunOverlayProject(
            videos: [
                VideoItem(
                    fileName: missingURL.lastPathComponent,
                    fileURL: missingURL,
                    metadata: VideoAssetMetadata(
                        durationSeconds: 5,
                        dimensions: PixelDimensions(width: 1_280, height: 720),
                        frameRate: 30,
                        capturedAt: nil,
                        hasAudio: false,
                        container: "MP4",
                        fileSizeBytes: 0
                    )
                )
            ]
        )
        let packageDirectory = root.appendingPathComponent("部分项目")

        let result = try ProjectPackageService().packageProject(
            project,
            to: packageDirectory,
            resolveURL: { _, _ in nil }
        )

        XCTAssertEqual(result.missingFiles, ["不存在.mp4"])
        XCTAssertEqual(result.copiedFileCount, 0)
        let saved = try ProjectFileCodec().load(from: result.projectURL)
        XCTAssertNil(saved.videos[0].resourceRelativePath)
        try? FileManager.default.removeItem(at: root)
    }

    func test原始素材被移动后可通过包内相对路径解析() throws {
        let root = try temporaryDirectory()
        let originalFolder = root.appendingPathComponent("原始")
        let packageFolder = root.appendingPathComponent("移动后的项目")
        try FileManager.default.createDirectory(
            at: originalFolder,
            withIntermediateDirectories: true
        )
        let sourceURL = originalFolder.appendingPathComponent("视频.mov")
        try Data("clip".utf8).write(to: sourceURL)
        let project = RunOverlayProject(
            videos: [
                VideoItem(
                    fileName: sourceURL.lastPathComponent,
                    fileURL: sourceURL,
                    metadata: VideoAssetMetadata(
                        durationSeconds: 1,
                        dimensions: PixelDimensions(width: 640, height: 480),
                        frameRate: 30,
                        capturedAt: nil,
                        hasAudio: false,
                        container: "MOV",
                        fileSizeBytes: 4
                    )
                )
            ]
        )
        let sourcePackage = root.appendingPathComponent("初始包")
        let result = try ProjectPackageService().packageProject(
            project,
            to: sourcePackage,
            resolveURL: { url, _ in url }
        )
        let packageProject = try ProjectFileCodec().load(from: result.projectURL)
        let packagedURL = result.projectURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                try XCTUnwrap(packageProject.videos[0].resourceRelativePath)
            )
        let movedURL = packageFolder.appendingPathComponent("素材/视频.mov")
        try FileManager.default.createDirectory(
            at: movedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: packagedURL, to: movedURL)
        try ProjectFileCodec().save(
            packageProject,
            to: packageFolder.appendingPathComponent("项目.runoverlay")
        )

        let reloadedProject = try ProjectFileCodec().load(
            from: packageFolder.appendingPathComponent("项目.runoverlay")
        )
        let relocation = ResourceRelocator().resolveProjectResources(
            reloadedProject,
            relativeTo: packageFolder
        )

        XCTAssertEqual(relocation.videoURLs[reloadedProject.videos[0].id], movedURL)
        XCTAssertTrue(relocation.missingVideoIDs.isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    func test项目包移动后仍能解析同名LRV() throws {
        let root = try temporaryDirectory()
        let originalDirectory = root.appendingPathComponent("original")
        try FileManager.default.createDirectory(
            at: originalDirectory,
            withIntermediateDirectories: true
        )
        let videoURL = originalDirectory.appendingPathComponent(
            "LRV_20260922_062216_378.mp4"
        )
        let sidecarURL = originalDirectory.appendingPathComponent(
            "LRV_20260922_062216_378.lrv"
        )
        try Data("video".utf8).write(to: videoURL)
        try Data("time-resource".utf8).write(to: sidecarURL)
        let timestamp = try XCTUnwrap(
            VideoTimeResourceReader().capturedAt(from: sidecarURL)
        )
        let item = VideoItem(
            fileName: videoURL.lastPathComponent,
            fileURL: videoURL,
            metadata: VideoAssetMetadata(
                durationSeconds: 5,
                dimensions: PixelDimensions(width: 960, height: 540),
                frameRate: 30,
                capturedAt: nil,
                hasAudio: false,
                container: "MP4",
                fileSizeBytes: 5
            ),
            timeResource: VideoTimeResource(
                fileName: sidecarURL.lastPathComponent,
                fileURL: sidecarURL,
                capturedAt: timestamp
            )
        )
        let project = RunOverlayProject(videos: [item])
        let packageURL = root.appendingPathComponent("first-package")
        let result = try ProjectPackageService().packageProject(
            project,
            to: packageURL,
            resolveURL: { url, _ in url }
        )

        XCTAssertEqual(result.copiedFileCount, 2)
        let packagedProject = try ProjectFileCodec().load(from: result.projectURL)
        let movedPackageURL = root.appendingPathComponent("moved-package")
        try FileManager.default.moveItem(at: packageURL, to: movedPackageURL)
        let relocation = ResourceRelocator().resolveProjectResources(
            packagedProject,
            relativeTo: movedPackageURL
        )
        let resolvedSidecar = try XCTUnwrap(
            relocation.sidecarURLs[packagedProject.videos[0].id]
        )

        XCTAssertEqual(resolvedSidecar.lastPathComponent, sidecarURL.lastPathComponent)
        XCTAssertEqual(
            VideoTimeResourceReader().capturedAt(from: resolvedSidecar),
            timestamp
        )
        try? FileManager.default.removeItem(at: root)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
