import Foundation
import XCTest
@testable import RunOverlayCore

final class MediaDropScannerTests: XCTestCase {
    func test递归扫描文件夹并分类媒体项目() throws {
        let root = try temporaryDirectory()
        let nested = root.appendingPathComponent("相机A/上午", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true
        )
        let video = nested.appendingPathComponent("跑步.MP4")
        let activity = nested.appendingPathComponent("活动.fit")
        let project = root.appendingPathComponent("行程.runoverlay")
        let ignored = root.appendingPathComponent("说明.txt")
        for url in [video, activity, project, ignored] {
            try Data().write(to: url)
        }

        let result = MediaDropScanner().scan([root, video])

        XCTAssertEqual(result.videoURLs.count, 1)
        XCTAssertEqual(
            result.activityURLs.map(\.standardizedFileURL),
            [activity.standardizedFileURL]
        )
        XCTAssertEqual(
            result.projectURLs.map(\.standardizedFileURL),
            [project.standardizedFileURL]
        )
        XCTAssertEqual(result.ignoredItemCount, 1)
        try? FileManager.default.removeItem(at: root)
    }

    func test直接拖入多个文件也会正确分类() throws {
        let root = try temporaryDirectory()
        let video = root.appendingPathComponent("跑步.mov")
        let gpx = root.appendingPathComponent("运动.gpx")
        let ignored = root.appendingPathComponent("封面.png")
        for url in [video, gpx, ignored] {
            try Data().write(to: url)
        }

        let result = MediaDropScanner().scan([video, gpx, ignored])

        XCTAssertEqual(
            result.videoURLs.map(\.standardizedFileURL),
            [video.standardizedFileURL]
        )
        XCTAssertEqual(result.activityURLs, [gpx])
        XCTAssertEqual(result.projectURLs, [])
        XCTAssertEqual(result.ignoredItemCount, 1)
        try? FileManager.default.removeItem(at: root)
    }

    func test同目录同名MP4与LRV按去除扩展名配对() throws {
        let root = try temporaryDirectory()
        let video = root.appendingPathComponent("LRV_20260922_062216_378.mp4")
        let sidecar = root.appendingPathComponent("LRV_20260922_062216_378.lrv")
        try Data().write(to: video)
        try Data().write(to: sidecar)

        let result = MediaDropScanner().scan([root])

        XCTAssertEqual(result.timeResourcesByVideoURL.count, 1)
        XCTAssertEqual(
            result.timeResourcesByVideoURL[
                video.resolvingSymlinksInPath().standardizedFileURL
            ]?
                .standardizedFileURL,
            sidecar.standardizedFileURL
        )
        XCTAssertTrue(result.unpairedTimeResourceURLs.isEmpty)
        XCTAssertEqual(result.ignoredItemCount, 0)
        try? FileManager.default.removeItem(at: root)
    }

    func test两组视频和时间资源按名称分别配对() throws {
        let root = try temporaryDirectory()
        let video1 = root.appendingPathComponent("LRV_20260922_062216_378.mp4")
        let video2 = root.appendingPathComponent("LRV_20260922_062457_379.mp4")
        let sidecar1 = root.appendingPathComponent("LRV_20260922_062216_378.lrv")
        let sidecar2 = root.appendingPathComponent("LRV_20260922_062457_379.lrv")
        for url in [video1, video2, sidecar1, sidecar2] {
            try Data().write(to: url)
        }

        let result = MediaDropScanner().scan([root])

        XCTAssertEqual(result.timeResourcesByVideoURL.count, 2)
        XCTAssertEqual(
            result.timeResourcesByVideoURL[
                video1.resolvingSymlinksInPath().standardizedFileURL
            ]?
                .standardizedFileURL,
            sidecar1.standardizedFileURL
        )
        XCTAssertEqual(
            result.timeResourcesByVideoURL[
                video2.resolvingSymlinksInPath().standardizedFileURL
            ]?
                .standardizedFileURL,
            sidecar2.standardizedFileURL
        )
        XCTAssertTrue(result.unpairedTimeResourceURLs.isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    func test大疆同名MP4与LRF无视扩展名大小写分别配对() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let names = [
            "DJI_20261002111755_0086_D",
            "DJI_20261002111832_0087_D"
        ]
        let pairs = names.map { name in
            (
                root.appendingPathComponent("\(name).MP4"),
                root.appendingPathComponent("\(name).LRF")
            )
        }
        for (video, sidecar) in pairs {
            try Data().write(to: video)
            try Data().write(to: sidecar)
        }

        let batch = MediaDropScanner().scan([root])

        XCTAssertEqual(batch.videoURLs.count, 2)
        XCTAssertEqual(batch.timeResourcesByVideoURL.count, 2)
        for (video, sidecar) in pairs {
            XCTAssertEqual(
                batch.timeResourcesByVideoURL[
                    video.resolvingSymlinksInPath().standardizedFileURL
                ]?.standardizedFileURL,
                sidecar.standardizedFileURL
            )
        }
        XCTAssertTrue(batch.unpairedTimeResourceURLs.isEmpty)
        XCTAssertTrue(batch.ambiguousVideoURLs.isEmpty)
        XCTAssertEqual(batch.ignoredItemCount, 0)
    }

    func test同名LRV和LRF同时存在时不猜测配对() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let video = root.appendingPathComponent("DJI_20261002111755_0086_D.MP4")
        let lrv = root.appendingPathComponent("DJI_20261002111755_0086_D.LRV")
        let lrf = root.appendingPathComponent("DJI_20261002111755_0086_D.LRF")
        for url in [video, lrv, lrf] {
            try Data().write(to: url)
        }

        let batch = MediaDropScanner().scan([root])

        XCTAssertEqual(batch.videoURLs.count, 1)
        XCTAssertTrue(batch.timeResourcesByVideoURL.isEmpty)
        XCTAssertEqual(batch.ambiguousVideoURLs, [video.standardizedFileURL])
        XCTAssertEqual(batch.unpairedTimeResourceURLs.count, 2)
    }

    func test影石VID视频与同时间戳LRV配对() throws {
        let root = try temporaryDirectory()
        let video = root.appendingPathComponent("VID_20260922_062216_378.mp4")
        let sidecar = root.appendingPathComponent("LRV_20260922_062216_378.lrv")
        try Data().write(to: video)
        try Data().write(to: sidecar)

        let result = MediaDropScanner().scan([root])

        XCTAssertEqual(
            result.videoURLs.map(\.standardizedFileURL),
            [video.standardizedFileURL]
        )
        XCTAssertEqual(
            result.timeResourcesByVideoURL[video.standardizedFileURL]?
                .standardizedFileURL,
            sidecar.standardizedFileURL
        )
        XCTAssertTrue(result.unpairedTimeResourceURLs.isEmpty)
        XCTAssertEqual(result.ignoredItemCount, 0)
        try? FileManager.default.removeItem(at: root)
    }

    func test影石无扩展名VID视频与同时间戳LRV配对() throws {
        let root = try temporaryDirectory()
        let video = root.appendingPathComponent("VID_20260922_062216_378")
        let sidecar = root.appendingPathComponent("LRV_20260922_062216_378.lrv")
        try Data().write(to: video)
        try Data().write(to: sidecar)

        let result = MediaDropScanner().scan([root])

        XCTAssertEqual(
            result.videoURLs.map(\.standardizedFileURL),
            [video.standardizedFileURL]
        )
        XCTAssertEqual(
            result.timeResourcesByVideoURL[video.standardizedFileURL]?
                .standardizedFileURL,
            sidecar.standardizedFileURL
        )
        XCTAssertTrue(result.unpairedTimeResourceURLs.isEmpty)
        XCTAssertEqual(result.ignoredItemCount, 0)
        try? FileManager.default.removeItem(at: root)
    }

    func test只配对视频所在目录中的同名LRV() throws {
        let root = try temporaryDirectory()
        let video = root.appendingPathComponent("片段.mp4")
        let firstSidecar = root.appendingPathComponent("片段.lrv")
        let secondFolder = root.appendingPathComponent("备份", isDirectory: true)
        try FileManager.default.createDirectory(
            at: secondFolder,
            withIntermediateDirectories: true
        )
        let secondSidecar = secondFolder.appendingPathComponent("片段.lrv")
        for url in [video, firstSidecar, secondSidecar] {
            try Data().write(to: url)
        }

        let result = MediaDropScanner().scan([root])

        XCTAssertEqual(
            result.timeResourcesByVideoURL[video.standardizedFileURL]?
                .standardizedFileURL,
            firstSidecar.standardizedFileURL
        )
        XCTAssertTrue(result.ambiguousVideoURLs.isEmpty)
        XCTAssertEqual(
            result.unpairedTimeResourceURLs.map(\.standardizedFileURL),
            [secondSidecar.standardizedFileURL]
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
