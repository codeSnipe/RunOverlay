import Foundation

public struct ProjectResourceStatus: Equatable, Sendable {
    public let missingVideoIDs: Set<UUID>
    public let missingTimeResourceVideoIDs: Set<UUID>
    public let isActivitySourceMissing: Bool

    public init(
        project: RunOverlayProject,
        videoURL: (VideoItem) -> URL,
        timeResourceURL: (VideoTimeResource) -> URL,
        activityURL: (ActivitySource) -> URL,
        isReadable: (URL) -> Bool
    ) {
        missingVideoIDs = Set(project.videos.compactMap { video in
            isReadable(videoURL(video)) ? nil : video.id
        })
        missingTimeResourceVideoIDs = Set(project.videos.compactMap { video in
            guard let resource = video.timeResource,
                  !isReadable(timeResourceURL(resource)) else {
                return nil
            }
            return video.id
        })
        isActivitySourceMissing = project.activitySource.map {
            !isReadable(activityURL($0))
        } ?? false
    }
}
