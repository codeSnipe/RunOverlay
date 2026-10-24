import Foundation

public enum OverlayDraftTransferError: LocalizedError, Equatable {
    case invalidFileType
    case unsupportedSchema(Int)
    case fileTooLarge
    case invalidTemplate
    case invalidName
    case invalidConfiguration
    case destinationAlreadyExists

    public var errorDescription: String? {
        switch self {
        case .invalidFileType:
            RunOverlayLocalization.text("error.template.invalidFileType")
        case let .unsupportedSchema(version):
            RunOverlayLocalization.format(
                "error.template.unsupportedSchema",
                arguments: [version]
            )
        case .fileTooLarge:
            RunOverlayLocalization.text("error.template.fileTooLarge")
        case .invalidTemplate:
            RunOverlayLocalization.text("error.template.invalidTemplate")
        case .invalidName:
            RunOverlayLocalization.text("error.template.invalidName")
        case .invalidConfiguration:
            RunOverlayLocalization.text("error.template.invalidConfiguration")
        case .destinationAlreadyExists:
            RunOverlayLocalization.text("error.template.destinationAlreadyExists")
        }
    }
}

public struct OverlayDraftTransferService: Sendable {
    public static let fileExtension = "runoverlay-template"
    public static let maximumFileSize = 1_048_576

    public init() {}

    /// 同时支持单个草稿文件与文件夹；文件夹递归扫描，忽略隐藏文件和包内文件。
    public func templateFiles(
        in selectedURLs: [URL],
        fileManager: FileManager = .default
    ) -> [URL] {
        var seen: Set<URL> = []
        var files: [URL] = []
        for selectedURL in selectedURLs {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: selectedURL.path,
                isDirectory: &isDirectory
            ) else { continue }
            if isDirectory.boolValue {
                guard let enumerator = fileManager.enumerator(
                    at: selectedURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .isPackageKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let file as URL in enumerator {
                    guard file.pathExtension.lowercased() == Self.fileExtension,
                          (try? file.resourceValues(forKeys: [.isRegularFileKey]))?
                            .isRegularFile == true else { continue }
                    let normalized = file.standardizedFileURL
                    if seen.insert(normalized).inserted {
                        files.append(file)
                    }
                }
            } else if selectedURL.pathExtension.lowercased() == Self.fileExtension {
                let normalized = selectedURL.standardizedFileURL
                if seen.insert(normalized).inserted {
                    files.append(selectedURL)
                }
            }
        }
        return files.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    public func encode(_ draft: OverlayDraft) throws -> Data {
        let template = OverlayDraftTemplate(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            configuration: draft.configuration
        )
        try validate(template)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(template)
        guard data.count <= Self.maximumFileSize else {
            throw OverlayDraftTransferError.fileTooLarge
        }
        return data
    }

    public func decode(_ data: Data) throws -> OverlayDraftTemplate {
        guard data.count <= Self.maximumFileSize else {
            throw OverlayDraftTransferError.fileTooLarge
        }

        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw OverlayDraftTransferError.invalidTemplate
            }
            root = object
        } catch {
            throw OverlayDraftTransferError.invalidTemplate
        }

        guard Set(root.keys) == ["schemaVersion", "name", "configuration"],
              let schemaVersion = root["schemaVersion"] as? Int
        else {
            throw OverlayDraftTransferError.invalidTemplate
        }
        guard schemaVersion == OverlayDraftTemplate.currentSchemaVersion else {
            throw OverlayDraftTransferError.unsupportedSchema(schemaVersion)
        }
        try validateJSONShape(root)

        let template: OverlayDraftTemplate
        do {
            template = try JSONDecoder().decode(OverlayDraftTemplate.self, from: data)
        } catch {
            throw OverlayDraftTransferError.invalidTemplate
        }
        try validate(template)
        return template
    }

    public func save(_ draft: OverlayDraft, to url: URL) throws {
        guard url.pathExtension.lowercased() == Self.fileExtension else {
            throw OverlayDraftTransferError.invalidFileType
        }
        let data = try encode(draft)
        do {
            // 只写保存面板授权的文件路径；不能与 .atomic 混用。
            try data.write(to: url, options: [.withoutOverwriting])
        } catch {
            if FileManager.default.fileExists(atPath: url.path) {
                throw OverlayDraftTransferError.destinationAlreadyExists
            }
            throw error
        }
    }

    public func load(from url: URL) throws -> OverlayDraftTemplate {
        guard url.pathExtension.lowercased() == Self.fileExtension else {
            throw OverlayDraftTransferError.invalidFileType
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: Self.maximumFileSize + 1) ?? Data()
        return try decode(data)
    }

    @discardableResult
    public func importTemplate(
        from url: URL,
        into library: inout OverlayDraftLibrary
    ) throws -> OverlayDraftImportResult {
        try importTemplate(load(from: url), into: &library)
    }

    @discardableResult
    public func importTemplate(
        _ template: OverlayDraftTemplate,
        into library: inout OverlayDraftLibrary
    ) throws -> OverlayDraftImportResult {
        try validate(template)
        let name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = name
        var index = 2
        while let existing = library.drafts.first(where: { $0.name == candidate }) {
            if existing.configuration == template.configuration {
                return .alreadyExists(existing)
            }
            let suffix = RunOverlayLocalization.format(
                "template.importSuffix",
                arguments: [index]
            )
            candidate = String(name.prefix(max(1, 80 - suffix.count))) + suffix
            index += 1
        }
        let draft = OverlayDraft(name: candidate, configuration: template.configuration)
        library.add(draft, makeDefault: false)
        return .imported(draft)
    }

    private func validate(_ template: OverlayDraftTemplate) throws {
        guard template.schemaVersion == OverlayDraftTemplate.currentSchemaVersion else {
            throw OverlayDraftTransferError.unsupportedSchema(template.schemaVersion)
        }
        let name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.count <= 80,
              !name.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              })
        else {
            throw OverlayDraftTransferError.invalidName
        }
        let configuration = template.configuration
        guard isHexColor(configuration.accentHex),
              isHexColor(configuration.foregroundHex),
              (1...64).contains(configuration.elements.count),
              Set(configuration.elements.map(\.id)).count == configuration.elements.count
        else {
            throw OverlayDraftTransferError.invalidConfiguration
        }
        for element in configuration.elements {
            let frame = element.frame
            guard frame.x.isFinite, frame.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite,
                  (0...1).contains(frame.x), (0...1).contains(frame.y),
                  frame.width > 0, frame.height > 0,
                  frame.x + frame.width <= 1.000_001,
                  frame.y + frame.height <= 1.000_001,
                  element.opacity.isFinite, (0...1).contains(element.opacity),
                  element.backgroundOpacity.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
                  element.textScale.isFinite, (0.5...2).contains(element.textScale),
                  element.measurementUnit.map({
                      element.kind.supportedMeasurementUnits.contains($0)
                  }) ?? true,
                  (element.kind == .clockTime || element.clockDisplay == .dateTime),
                  (element.kind == .elapsedTime || element.durationDisplay == .adaptive)
            else {
                throw OverlayDraftTransferError.invalidConfiguration
            }
        }
    }

    private func isHexColor(_ hex: String) -> Bool {
        hex.count == 7 && hex.first == "#" &&
            hex.dropFirst().allSatisfy {
                $0.isASCII && $0.isHexDigit
            }
    }

    private func validateJSONShape(_ root: [String: Any]) throws {
        guard let configuration = root["configuration"] as? [String: Any],
              Set(configuration.keys) == ["preset", "accentHex", "foregroundHex", "elements"],
              let elements = configuration["elements"] as? [[String: Any]]
        else {
            throw OverlayDraftTransferError.invalidTemplate
        }
        for element in elements {
            let required: Set<String> = ["id", "kind", "frame", "isVisible", "opacity"]
            let allowed = required.union([
                "backgroundOpacity", "textScale", "measurementUnit",
                "clockDisplay", "durationDisplay"
            ])
            guard required.isSubset(of: Set(element.keys)),
                  Set(element.keys).isSubset(of: allowed),
                  let frame = element["frame"] as? [String: Any],
                  Set(frame.keys) == ["x", "y", "width", "height"]
            else {
                throw OverlayDraftTransferError.invalidTemplate
            }
        }
    }
}
