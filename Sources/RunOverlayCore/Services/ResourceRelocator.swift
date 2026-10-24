import Foundation

public struct ResourceRelocationResult: Sendable {
    public var activityURL: URL?
    public var videoURLs: [UUID: URL]
    public var sidecarURLs: [UUID: URL]
    public var coverSourceURLs: [UUID: URL]
    public var coverExportURLs: [UUID: URL]
    public var missingVideoIDs: [UUID]

    public init(
        activityURL: URL?,
        videoURLs: [UUID: URL],
        sidecarURLs: [UUID: URL] = [:],
        coverSourceURLs: [UUID: URL] = [:],
        coverExportURLs: [UUID: URL] = [:],
        missingVideoIDs: [UUID]
    ) {
        self.activityURL = activityURL
        self.videoURLs = videoURLs
        self.sidecarURLs = sidecarURLs
        self.coverSourceURLs = coverSourceURLs
        self.coverExportURLs = coverExportURLs
        self.missingVideoIDs = missingVideoIDs
    }
}

public struct ResourceRelocator: Sendable {
    public init() {}

    public func resolveProjectResources(
        _ project: RunOverlayProject,
        relativeTo packageDirectory: URL,
        fileManager: FileManager = .default
    ) -> ResourceRelocationResult {
        var activityURL: URL?
        if let source = project.activitySource {
            activityURL = resolve(
                url: source.fileURL,
                relativePath: source.resourceRelativePath,
                packageDirectory: packageDirectory,
                fileManager: fileManager
            )
        }

        var videoURLs: [UUID: URL] = [:]
        var sidecarURLs: [UUID: URL] = [:]
        var coverSourceURLs: [UUID: URL] = [:]
        var coverExportURLs: [UUID: URL] = [:]
        var missingVideoIDs: [UUID] = []
        for video in project.videos {
            if let url = resolve(
                url: video.fileURL,
                relativePath: video.resourceRelativePath,
                packageDirectory: packageDirectory,
                fileManager: fileManager
            ) {
                videoURLs[video.id] = url
            } else {
                missingVideoIDs.append(video.id)
            }
            if let resource = video.timeResource,
               let url = resolve(
                url: resource.fileURL,
                relativePath: resource.resourceRelativePath,
                packageDirectory: packageDirectory,
                fileManager: fileManager
               ) {
                sidecarURLs[video.id] = url
            }
            if let cover = video.cover {
                if case let .image(source) = cover.source,
                   let url = resolve(
                    url: source.fileURL,
                    relativePath: source.resourceRelativePath,
                    packageDirectory: packageDirectory,
                    fileManager: fileManager
                   ) {
                    coverSourceURLs[video.id] = url
                }
                if let exported = cover.exportedImage,
                   let url = resolve(
                    url: exported.fileURL,
                    relativePath: exported.resourceRelativePath,
                    packageDirectory: packageDirectory,
                    fileManager: fileManager
                   ) {
                    coverExportURLs[video.id] = url
                }
            }
        }

        return ResourceRelocationResult(
            activityURL: activityURL,
            videoURLs: videoURLs,
            sidecarURLs: sidecarURLs,
            coverSourceURLs: coverSourceURLs,
            coverExportURLs: coverExportURLs,
            missingVideoIDs: missingVideoIDs
        )
    }

    private func resolve(
        url: URL,
        relativePath: String?,
        packageDirectory: URL,
        fileManager: FileManager
    ) -> URL? {
        if let relativePath {
            let candidate = packageDirectory.appendingPathComponent(relativePath)
                .standardizedFileURL
            if candidate.path.hasPrefix(packageDirectory.standardizedFileURL.path + "/"),
               fileManager.isReadableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return fileManager.isReadableFile(atPath: url.path) ? url : nil
    }
}
