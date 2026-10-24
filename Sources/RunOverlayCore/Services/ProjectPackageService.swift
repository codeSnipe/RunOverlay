import Foundation

public enum ProjectPackageError: LocalizedError {
    case destinationAlreadyExists

    public var errorDescription: String? {
        switch self {
        case .destinationAlreadyExists:
            RunOverlayLocalization.text("error.packageDestinationExists")
        }
    }
}

public struct ProjectPackageResult: Sendable {
    public var projectURL: URL
    public var copiedFileCount: Int
    public var totalBytes: Int64
    public var missingFiles: [String]

    public init(
        projectURL: URL,
        copiedFileCount: Int,
        totalBytes: Int64,
        missingFiles: [String]
    ) {
        self.projectURL = projectURL
        self.copiedFileCount = copiedFileCount
        self.totalBytes = totalBytes
        self.missingFiles = missingFiles
    }
}

public struct ProjectPackageService: Sendable {
    public init() {}

    public func packageProject(
        _ sourceProject: RunOverlayProject,
        to packageURL: URL,
        resolveURL: @Sendable (URL, Data?) -> URL?
    ) throws -> ProjectPackageResult {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: packageURL.path) else {
            throw ProjectPackageError.destinationAlreadyExists
        }
        let stagingURL = packageURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(packageURL.lastPathComponent).partial-\(UUID().uuidString)",
                isDirectory: true
            )
        var didCommitPackage = false
        defer {
            if !didCommitPackage {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        let fileURLs = uniqueResourceURLs(in: sourceProject)
        var requiredBytes: Int64 = 0
        var missingFiles: [String] = []

        for resource in fileURLs {
            guard let url = resolveURL(resource.url, resource.bookmarkData),
                  fileManager.isReadableFile(atPath: url.path)
            else {
                missingFiles.append(resource.fileName)
                continue
            }
            requiredBytes += fileSize(at: url)
        }
        for video in sourceProject.videos {
            if let sidecar = video.timeResource,
               let url = resolveURL(sidecar.fileURL, sidecar.bookmarkData),
               fileManager.isReadableFile(atPath: url.path) {
                requiredBytes += fileSize(at: url)
            }
        }

        let parentURL = packageURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parentURL,
            withIntermediateDirectories: true
        )
        let availableBytes = try fileManager.attributesOfFileSystem(
            forPath: parentURL.path
        )[.systemFreeSize] as? NSNumber
        if let availableBytes, availableBytes.int64Value < requiredBytes {
            throw CocoaError(.fileWriteOutOfSpace)
        }

        try fileManager.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false
        )
        let resourcesDirectory = stagingURL.appendingPathComponent(
            "素材",
            isDirectory: true
        )
        let timeResourcesDirectory = resourcesDirectory.appendingPathComponent(
            "时间资源",
            isDirectory: true
        )
        let coverResourcesDirectory = resourcesDirectory.appendingPathComponent(
            "封面",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: resourcesDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: timeResourcesDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: coverResourcesDirectory,
            withIntermediateDirectories: true
        )

        var project = sourceProject
        var copiedFileCount = 0
        var copiedBytes: Int64 = 0
        var usedNames: Set<String> = []

        if let source = project.activitySource {
            if let resolved = resolveURL(source.fileURL, source.bookmarkData),
               fileManager.isReadableFile(atPath: resolved.path) {
                let destination = uniqueDestination(
                    fileName: source.fileName,
                    directory: resourcesDirectory,
                    usedNames: &usedNames
                )
                try fileManager.copyItem(at: resolved, to: destination)
                copiedFileCount += 1
                copiedBytes += fileSize(at: resolved)
                project.activitySource?.fileURL = destination
                project.activitySource?.bookmarkData = try? bookmark(for: packageURL
                    .appendingPathComponent("素材")
                    .appendingPathComponent(destination.lastPathComponent))
                project.activitySource?.resourceRelativePath =
                    "素材/\(destination.lastPathComponent)"
            } else {
                project.activitySource?.bookmarkData = nil
                project.activitySource?.resourceRelativePath = nil
            }
        }

        for index in project.videos.indices {
            let original = sourceProject.videos[index]
            guard let resolved = resolveURL(original.fileURL, original.bookmarkData),
                  fileManager.isReadableFile(atPath: resolved.path)
            else {
                project.videos[index].bookmarkData = nil
                project.videos[index].resourceRelativePath = nil
                for resource in coverResources(of: original) {
                    missingFiles.append(resource.fileURL.lastPathComponent)
                }
                continue
            }

            let destination = uniqueDestination(
                fileName: original.fileName,
                directory: resourcesDirectory,
                usedNames: &usedNames
            )
            try fileManager.copyItem(at: resolved, to: destination)
            copiedFileCount += 1
            let size = fileSize(at: resolved)
            copiedBytes += size
            project.videos[index].fileURL = destination
            project.videos[index].bookmarkData = try? bookmark(for: packageURL
                .appendingPathComponent("素材")
                .appendingPathComponent(destination.lastPathComponent))
            project.videos[index].resourceRelativePath =
                "素材/\(destination.lastPathComponent)"

            if let originalTimeResource = original.timeResource {
                if let resolvedTimeResource = resolveURL(
                    originalTimeResource.fileURL,
                    originalTimeResource.bookmarkData
                ), fileManager.isReadableFile(atPath: resolvedTimeResource.path) {
                    let timeResourceDestination = uniqueDestination(
                        fileName: originalTimeResource.fileName,
                        directory: timeResourcesDirectory,
                        usedNames: &usedNames
                    )
                    try fileManager.copyItem(
                        at: resolvedTimeResource,
                        to: timeResourceDestination
                    )
                    copiedFileCount += 1
                    copiedBytes += fileSize(at: resolvedTimeResource)
                    project.videos[index].timeResource?.fileURL =
                        timeResourceDestination
                    project.videos[index].timeResource?.bookmarkData =
                        try? bookmark(
                            for: packageURL
                                .appendingPathComponent("素材")
                                .appendingPathComponent("时间资源")
                                .appendingPathComponent(
                                    timeResourceDestination.lastPathComponent
                                )
                        )
                    project.videos[index].timeResource?.resourceRelativePath =
                        "素材/时间资源/\(timeResourceDestination.lastPathComponent)"
                } else {
                    missingFiles.append(originalTimeResource.fileName)
                    project.videos[index].timeResource?.bookmarkData = nil
                    project.videos[index].timeResource?.resourceRelativePath = nil
                }
            }

            if let cover = original.cover {
                if case let .image(source) = cover.source {
                    project.videos[index].cover?.source = .image(
                        copyCoverResource(
                            source,
                            to: coverResourcesDirectory,
                            packageURL: packageURL,
                            resolveURL: resolveURL,
                            usedNames: &usedNames,
                            copiedFileCount: &copiedFileCount,
                            copiedBytes: &copiedBytes,
                            missingFiles: &missingFiles
                        )
                    )
                }
                if let exportedImage = cover.exportedImage {
                    project.videos[index].cover?.exportedImage = copyCoverResource(
                        exportedImage,
                        to: coverResourcesDirectory,
                        packageURL: packageURL,
                        resolveURL: resolveURL,
                        usedNames: &usedNames,
                        copiedFileCount: &copiedFileCount,
                        copiedBytes: &copiedBytes,
                        missingFiles: &missingFiles
                    )
                }
            }
        }

        project.updatedAt = Date()
        let stagedProjectURL = stagingURL.appendingPathComponent(
            "\(safeProjectName(project.name)).runoverlay"
        )
        try ProjectFileCodec().save(project, to: stagedProjectURL)
        try fileManager.moveItem(at: stagingURL, to: packageURL)
        didCommitPackage = true

        return ProjectPackageResult(
            projectURL: packageURL.appendingPathComponent(
                stagedProjectURL.lastPathComponent
            ),
            copiedFileCount: copiedFileCount,
            totalBytes: copiedBytes,
            missingFiles: missingFiles
        )
    }

    private func uniqueResourceURLs(
        in project: RunOverlayProject
    ) -> [(url: URL, bookmarkData: Data?, fileName: String)] {
        var resources: [(URL, Data?, String)] = []
        if let source = project.activitySource {
            resources.append((source.fileURL, source.bookmarkData, source.fileName))
        }
        resources.append(
            contentsOf: project.videos.flatMap { video in
                var entries: [(URL, Data?, String)] = [
                    (video.fileURL, video.bookmarkData, video.fileName)
                ]
                if let timeResource = video.timeResource {
                    entries.append(
                        (
                            timeResource.fileURL,
                            timeResource.bookmarkData,
                            "时间资源/\(video.fileName)/\(timeResource.fileName)"
                        )
                    )
                }
                entries.append(contentsOf: coverResources(of: video).map {
                    ($0.fileURL, $0.bookmarkData, "封面/\($0.fileURL.lastPathComponent)")
                })
                return entries
            }
        )
        var seen = Set<URL>()
        return resources.compactMap { resource in
            let standardized = resource.0.standardizedFileURL
            guard seen.insert(standardized).inserted else {
                return nil
            }
            return (standardized, resource.1, resource.2)
        }
    }

    private func coverResources(of video: VideoItem) -> [CoverImageResource] {
        guard let cover = video.cover else { return [] }
        var result: [CoverImageResource] = []
        if case let .image(source) = cover.source {
            result.append(source)
        }
        if let exported = cover.exportedImage {
            result.append(exported)
        }
        return result
    }

    private func copyCoverResource(
        _ resource: CoverImageResource,
        to directory: URL,
        packageURL: URL,
        resolveURL: @Sendable (URL, Data?) -> URL?,
        usedNames: inout Set<String>,
        copiedFileCount: inout Int,
        copiedBytes: inout Int64,
        missingFiles: inout [String]
    ) -> CoverImageResource {
        var updated = resource
        guard let resolved = resolveURL(resource.fileURL, resource.bookmarkData),
              FileManager.default.isReadableFile(atPath: resolved.path) else {
            missingFiles.append(resource.fileURL.lastPathComponent)
            updated.bookmarkData = nil
            updated.resourceRelativePath = nil
            return updated
        }
        let destination = uniqueDestination(
            fileName: resource.fileURL.lastPathComponent,
            directory: directory,
            usedNames: &usedNames
        )
        do {
            try FileManager.default.copyItem(at: resolved, to: destination)
            copiedFileCount += 1
            copiedBytes += fileSize(at: resolved)
            updated.fileURL = destination
            updated.bookmarkData = try? bookmark(
                for: packageURL
                    .appendingPathComponent("素材")
                    .appendingPathComponent("封面")
                    .appendingPathComponent(destination.lastPathComponent)
            )
            updated.resourceRelativePath = "素材/封面/\(destination.lastPathComponent)"
        } catch {
            missingFiles.append(resource.fileURL.lastPathComponent)
            updated.bookmarkData = nil
            updated.resourceRelativePath = nil
        }
        return updated
    }

    private func uniqueDestination(
        fileName: String,
        directory: URL,
        usedNames: inout Set<String>
    ) -> URL {
        let original = URL(fileURLWithPath: fileName)
        let base = original.deletingPathExtension().lastPathComponent
        let suffix = original.pathExtension
        var index = 1

        while true {
            let candidateName = index == 1
                ? fileName
                : "\(base)_\(index).\(suffix)"
            let candidate = directory.appendingPathComponent(candidateName)
            if usedNames.insert(candidateName).inserted,
               !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func safeProjectName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "RunOverlay 项目" : cleaned
    }

    private func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
