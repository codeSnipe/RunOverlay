import Foundation

public struct VideoListNavigation: Sendable {
    public init() {}

    public func adjacentVideoID(
        in videos: [VideoItem],
        currentID: UUID?,
        direction: Int
    ) -> UUID? {
        guard !videos.isEmpty, direction != 0 else {
            return nil
        }
        guard let currentIndex = videos.firstIndex(where: { $0.id == currentID }) else {
            return direction > 0 ? videos.first?.id : videos.last?.id
        }
        let nextIndex = currentIndex + (direction > 0 ? 1 : -1)
        guard videos.indices.contains(nextIndex) else {
            return nil
        }
        return videos[nextIndex].id
    }
}
