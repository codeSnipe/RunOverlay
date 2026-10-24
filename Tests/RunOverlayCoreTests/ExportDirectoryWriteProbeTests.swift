import Foundation
import XCTest
@testable import RunOverlayCore

final class ExportDirectoryWriteProbeTests: XCTestCase {
    func test有权限的目录验证后不残留临时文件() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        try ExportDirectoryWriteProbe().verify(directory)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ).isEmpty)
        try ExportDirectoryWriteProbe().verify(directory)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ).isEmpty)
    }

    func test普通文件或不存在的目录被拒绝() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("不是目录")
        try Data([0x01]).write(to: file)
        XCTAssertThrowsError(try ExportDirectoryWriteProbe().verify(file))
        XCTAssertEqual(try Data(contentsOf: file), Data([0x01]))
        XCTAssertThrowsError(try ExportDirectoryWriteProbe().verify(
            directory.appendingPathComponent("不存在", isDirectory: true)
        ))
    }

    func test不可写的目录会在生成导出任务前被拒绝() throws {
        guard getuid() != 0 else {
            throw XCTSkip("特权进程不受普通目录权限限制")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )

        XCTAssertThrowsError(try ExportDirectoryWriteProbe().verify(directory))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ).isEmpty)
    }
}
