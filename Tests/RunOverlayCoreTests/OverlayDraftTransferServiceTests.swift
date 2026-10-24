import Foundation
import XCTest
@testable import RunOverlayCore

final class OverlayDraftTransferServiceTests: XCTestCase {
    private let service = OverlayDraftTransferService()

    func test选择文件夹递归导入草稿并忽略无关文件() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let nested = folder.appendingPathComponent("其他人分享", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true
        )
        let first = folder.appendingPathComponent("晨跑.runoverlay-template")
        let second = nested.appendingPathComponent("夜跑.RUNOVERLAY-TEMPLATE")
        try service.encode(
            OverlayDraft(name: "晨跑", configuration: .preset(.sport))
        ).write(to: first)
        try service.encode(
            OverlayDraft(name: "夜跑", configuration: .preset(.minimal))
        ).write(to: second)
        try Data("忽略".utf8).write(to: nested.appendingPathComponent("说明.txt"))

        let files = service.templateFiles(in: [folder, first])
        XCTAssertEqual(
            Set(files.map(\.standardizedFileURL)),
            Set([first, second].map(\.standardizedFileURL))
        )
        var library = OverlayDraftLibrary()
        for file in files {
            _ = try service.importTemplate(from: file, into: &library)
        }
        XCTAssertEqual(Set(library.drafts.map(\.name)), ["晨跑", "夜跑"])
        XCTAssertEqual(service.templateFiles(in: [nested.appendingPathComponent("说明.txt")]), [])
    }

    func test导出只包含蒙层名称配置且可以分享导入() throws {
        let source = OverlayDraft(
            id: UUID(),
            name: "  雨夜跑步  ",
            configuration: .preset(.sport),
            createdAt: Date(timeIntervalSince1970: 123)
        )
        let data = try service.encode(source)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(Set(json.keys), ["schemaVersion", "name", "configuration"])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["name"] as? String, "雨夜跑步")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(source.id.uuidString))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("fileURL"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("bookmarkData"))

        let template = try service.decode(data)
        var library = OverlayDraftLibrary()
        let result = try service.importTemplate(template, into: &library)
        guard case let .imported(draft) = result else {
            return XCTFail("应该导入草稿")
        }
        XCTAssertEqual(draft.name, "雨夜跑步")
        XCTAssertEqual(draft.configuration, source.configuration)
        XCTAssertNotEqual(draft.id, source.id)
        XCTAssertNil(library.defaultDraftID)
    }

    func test重复导入不新增草稿并不覆盖同名草稿() throws {
        let originalLanguage = RunOverlayLocalization.language
        RunOverlayLocalization.language = .chineseSimplified
        defer { RunOverlayLocalization.language = originalLanguage }

        let original = OverlayDraft(name: "晨跑", configuration: .preset(.minimal))
        var library = OverlayDraftLibrary(drafts: [original], defaultDraftID: original.id)
        let template = OverlayDraftTemplate(
            name: "晨跑",
            configuration: .preset(.sport)
        )

        let first = try service.importTemplate(template, into: &library)
        guard case let .imported(imported) = first else {
            return XCTFail("同名不同配置仍应导入")
        }
        XCTAssertEqual(imported.name, "晨跑（导入 2）")
        XCTAssertEqual(library.drafts.count, 2)
        XCTAssertEqual(library.defaultDraftID, original.id)
        XCTAssertEqual(library.draft(withID: original.id), original)
        XCTAssertEqual(
            try service.importTemplate(template, into: &library),
            .alreadyExists(imported)
        )
        XCTAssertEqual(library.drafts.count, 2)
    }

    func test导出不覆盖已经存在的文件() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("晨跑.runoverlay-template")
        let existing = Data("重要原文件".utf8)
        try existing.write(to: url)

        XCTAssertThrowsError(
            try service.save(
                OverlayDraft(name: "晨跑", configuration: .preset(.sport)),
                to: url
            )
        ) { error in
            XCTAssertEqual(
                error as? OverlayDraftTransferError,
                .destinationAlreadyExists
            )
        }
        XCTAssertEqual(try Data(contentsOf: url), existing)
    }

    func test文件导出导入往返且导入不自动保存() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("海滨跑.runoverlay-template")
        let draft = OverlayDraft(name: "海滨跑", configuration: .preset(.technology))

        try service.save(draft, to: url)
        var library = OverlayDraftLibrary()
        let result = try service.importTemplate(from: url, into: &library)
        guard case let .imported(imported) = result else {
            return XCTFail("应该导入草稿")
        }
        XCTAssertEqual(imported.configuration, draft.configuration)
        XCTAssertEqual(library.drafts.count, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path)
        )
    }

    func test分享模板保留卡片专属属性且旧模板可读() throws {
        var configuration = OverlayConfiguration.preset(.sport)
        configuration.elements[0].textScale = 1.4
        let paceIndex = try XCTUnwrap(configuration.elements.firstIndex {
            $0.kind == .pace
        })
        configuration.elements[paceIndex].measurementUnit = .miles
        let clockIndex = try XCTUnwrap(configuration.elements.firstIndex {
            $0.kind == .clockTime
        })
        configuration.elements[clockIndex].clockDisplay = .time
        let exported = try service.encode(
            OverlayDraft(name: "独立样式", configuration: configuration)
        )
        let decoded = try service.decode(exported)
        XCTAssertEqual(decoded.configuration.elements[0].textScale, 1.4)
        XCTAssertEqual(
            decoded.configuration.elements[paceIndex].effectiveMeasurementUnit,
            .miles
        )
        XCTAssertEqual(decoded.configuration.elements[clockIndex].clockDisplay, .time)

        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: exported) as? [String: Any]
        )
        var payload = try XCTUnwrap(json["configuration"] as? [String: Any])
        var elements = try XCTUnwrap(payload["elements"] as? [[String: Any]])
        for index in elements.indices {
            elements[index].removeValue(forKey: "textScale")
            elements[index].removeValue(forKey: "measurementUnit")
            elements[index].removeValue(forKey: "clockDisplay")
            elements[index].removeValue(forKey: "durationDisplay")
        }
        payload["elements"] = elements
        json["configuration"] = payload
        let legacy = try service.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.configuration.elements.allSatisfy { $0.textScale == 1 })
        XCTAssertTrue(legacy.configuration.elements.allSatisfy {
            $0.measurementUnit == nil
        })
        XCTAssertTrue(legacy.configuration.elements.allSatisfy {
            $0.clockDisplay == .dateTime && $0.durationDisplay == .adaptive
        })
    }

    func test拒绝缺失错误或未来版本且保留原库() throws {
        var library = OverlayDraftLibrary(drafts: [
            OverlayDraft(name: "原草稿", configuration: .preset(.minimal))
        ])
        let before = library
        let valid = try service.encode(
            OverlayDraft(name: "新的", configuration: .preset(.technology))
        )
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: valid) as? [String: Any]
        )
        json["schemaVersion"] = 2
        XCTAssertThrowsError(
            try service.importTemplate(
                service.decode(JSONSerialization.data(withJSONObject: json)),
                into: &library
            )
        ) { error in
            XCTAssertEqual(error as? OverlayDraftTransferError, .unsupportedSchema(2))
        }
        XCTAssertEqual(library, before)

        json.removeValue(forKey: "schemaVersion")
        XCTAssertThrowsError(try service.decode(JSONSerialization.data(withJSONObject: json))) {
            XCTAssertEqual($0 as? OverlayDraftTransferError, .invalidTemplate)
        }
        json["schemaVersion"] = 1
        json["project"] = ["fileURL": "/Users/runner/private.mov"]
        XCTAssertThrowsError(try service.decode(JSONSerialization.data(withJSONObject: json))) {
            XCTAssertEqual($0 as? OverlayDraftTransferError, .invalidTemplate)
        }
    }

    func test拒绝超大文件与空名称() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("过大.runoverlay-template")
        try Data(repeating: 0, count: OverlayDraftTransferService.maximumFileSize + 1)
            .write(to: url)
        XCTAssertThrowsError(try service.load(from: url)) {
            XCTAssertEqual($0 as? OverlayDraftTransferError, .fileTooLarge)
        }

        let invalidName = OverlayDraftTemplate(
            name: " \n\t ",
            configuration: .preset(.minimal)
        )
        var library = OverlayDraftLibrary()
        XCTAssertThrowsError(try service.importTemplate(invalidName, into: &library)) {
            XCTAssertEqual($0 as? OverlayDraftTransferError, .invalidName)
        }
        XCTAssertTrue(library.drafts.isEmpty)
    }

    func test拒绝无效布局和未知嵌套字段() throws {
        var config = OverlayConfiguration.preset(.sport)
        config.elements[0].frame.width = .infinity
        XCTAssertThrowsError(
            try service.encode(OverlayDraft(name: "坏配置", configuration: config))
        ) {
            XCTAssertEqual($0 as? OverlayDraftTransferError, .invalidConfiguration)
        }

        config = .preset(.sport)
        config.elements[0].textScale = 3
        XCTAssertThrowsError(
            try service.encode(OverlayDraft(name: "过大的文字", configuration: config))
        ) {
            XCTAssertEqual($0 as? OverlayDraftTransferError, .invalidConfiguration)
        }

        config = .preset(.sport)
        config.elements[0].measurementUnit = .miles
        XCTAssertThrowsError(
            try service.encode(OverlayDraft(name: "轨迹不能使用英里单位", configuration: config))
        ) {
            XCTAssertEqual($0 as? OverlayDraftTransferError, .invalidConfiguration)
        }

        config = .preset(.sport)
        config.elements[0].clockDisplay = .date
        XCTAssertThrowsError(
            try service.encode(OverlayDraft(name: "轨迹不能显示日期", configuration: config))
        ) {
            XCTAssertEqual($0 as? OverlayDraftTransferError, .invalidConfiguration)
        }

        let valid = try service.encode(
            OverlayDraft(name: "有效", configuration: .preset(.sport))
        )
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: valid) as? [String: Any]
        )
        var configJSON = try XCTUnwrap(json["configuration"] as? [String: Any])
        var elements = try XCTUnwrap(configJSON["elements"] as? [[String: Any]])
        elements[0]["fileURL"] = "file:///Users/runner/private.mov"
        configJSON["elements"] = elements
        json["configuration"] = configJSON
        XCTAssertThrowsError(try service.decode(JSONSerialization.data(withJSONObject: json))) {
            XCTAssertEqual($0 as? OverlayDraftTransferError, .invalidTemplate)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "OverlayDraftTransferTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }
}
