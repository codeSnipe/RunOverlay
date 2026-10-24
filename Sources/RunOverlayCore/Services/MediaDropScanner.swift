import Foundation

public struct MediaDropBatch: Equatable, Sendable {
    public var videoURLs: [URL]
    public var timeResourcesByVideoURL: [URL: URL]
    public var unpairedTimeResourceURLs: [URL]
    public var ambiguousVideoURLs: [URL]
    public var activityURLs: [URL]
    public var projectURLs: [URL]
    public var ignoredItemCount: Int

    public init(
        videoURLs: [URL],
        timeResourcesByVideoURL: [URL: URL] = [:],
        unpairedTimeResourceURLs: [URL] = [],
        ambiguousVideoURLs: [URL] = [],
        activityURLs: [URL],
        projectURLs: [URL],
        ignoredItemCount: Int
    ) {
        self.videoURLs = videoURLs
        self.timeResourcesByVideoURL = timeResourcesByVideoURL
        self.unpairedTimeResourceURLs = unpairedTimeResourceURLs
        self.ambiguousVideoURLs = ambiguousVideoURLs
        self.activityURLs = activityURLs
        self.projectURLs = projectURLs
        self.ignoredItemCount = ignoredItemCount
    }
}

public struct MediaDropScanner: Sendable {
    private let supportedVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    private let supportedActivityExtensions: Set<String> = ["fit", "gpx"]
    private let supportedProjectExtensions: Set<String> = ["runoverlay"]
    private let insta360TimestampPattern = #"^(?:LRV|VID)_(\d{8}_\d{6}_\d{3})$"#

    public init() {}

    public func scan(
        _ droppedURLs: [URL],
        fileManager: FileManager = .default
    ) -> MediaDropBatch {
        var videos: [URL] = []
        var timeResources: [URL] = []
        var activities: [URL] = []
        var projects: [URL] = []
        var ignoredItemCount = 0
        var seenURLs: Set<URL> = []

        for droppedURL in droppedURLs {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(
                atPath: droppedURL.path,
                isDirectory: &isDirectory
            )
            let candidates: [URL]
            if exists && isDirectory.boolValue {
                candidates = enumerateFiles(in: droppedURL, fileManager: fileManager)
            } else {
                candidates = [droppedURL]
            }

            for candidate in candidates {
                let standardizedURL = candidate.standardizedFileURL
                guard seenURLs.insert(standardizedURL).inserted else {
                    continue
                }

                let fileExtension = candidate.pathExtension.lowercased()
                if supportedVideoExtensions.contains(fileExtension) ||
                    (fileExtension.isEmpty && isInsta360VideoName(candidate.lastPathComponent)) {
                    videos.append(candidate)
                } else if VideoTimeResourceReader.supportedExtensions.contains(fileExtension) {
                    timeResources.append(candidate)
                } else if supportedActivityExtensions.contains(fileExtension) {
                    activities.append(candidate)
                } else if supportedProjectExtensions.contains(fileExtension) {
                    projects.append(candidate)
                } else {
                    ignoredItemCount += 1
                }
            }
        }

        let sortedVideos = videos.sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
        let sortedTimeResources = timeResources.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        let sidecarsByFolderAndName = Dictionary(grouping: sortedTimeResources) {
            pairingKey(for: $0.lastPathComponent, in: $0)
        }
        var timeResourcesByVideoURL: [URL: URL] = [:]
        var pairedSidecars: Set<URL> = []
        var ambiguousVideoURLs: [URL] = []
        let reader = VideoTimeResourceReader()
        for videoURL in sortedVideos {
            let normalizedVideoURL = videoURL.resolvingSymlinksInPath()
                .standardizedFileURL
            let candidateNames = Set(reader.candidateFileNames(
                forVideoName: normalizedVideoURL.lastPathComponent
            ))
            let matches = candidateNames.flatMap { name in
                sidecarsByFolderAndName[
                    pairingKey(for: name, in: normalizedVideoURL)
                ] ?? []
            }
            guard !matches.isEmpty else {
                continue
            }
            guard matches.count == 1, let sidecar = matches.first else {
                ambiguousVideoURLs.append(normalizedVideoURL)
                continue
            }
            timeResourcesByVideoURL[normalizedVideoURL] = sidecar
            pairedSidecars.insert(sidecar.standardizedFileURL)
        }
        let unpairedSidecars = sortedTimeResources.filter {
            !pairedSidecars.contains($0.standardizedFileURL)
        }

        return MediaDropBatch(
            videoURLs: sortedVideos,
            timeResourcesByVideoURL: timeResourcesByVideoURL,
            unpairedTimeResourceURLs: unpairedSidecars,
            ambiguousVideoURLs: ambiguousVideoURLs,
            activityURLs: activities.sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            },
            projectURLs: projects.sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            },
            ignoredItemCount:
                ignoredItemCount +
                unpairedSidecars.count +
                ambiguousVideoURLs.count
        )
    }

    private func pairingKey(for fileName: String, in url: URL) -> String {
        let folder = url.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        return "\(folder)|\(fileName.lowercased())"
    }

    private func isInsta360VideoName(_ name: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: insta360TimestampPattern) else {
            return false
        }
        return expression.firstMatch(
            in: name,
            range: NSRange(name.startIndex..., in: name)
        ) != nil
    }

    private func enumerateFiles(
        in directory: URL,
        fileManager: FileManager
    ) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true ? url : nil
        }
    }
}
