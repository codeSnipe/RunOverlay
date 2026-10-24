import Foundation

public enum SmartEditDraftError: Error, Equatable {
    case unsupportedSchema
    case invalidDraft
}

public struct SmartEditDraftCodec: Sendable {
    public init() {}

    public func encode(_ draft: SmartEditDraft) throws -> Data {
        try validate(draft)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(draft)
    }

    public func decode(_ data: Data) throws -> SmartEditDraft {
        let draft: SmartEditDraft
        do {
            draft = try JSONDecoder().decode(SmartEditDraft.self, from: data)
        } catch {
            throw SmartEditDraftError.invalidDraft
        }
        try validate(draft)
        return draft
    }

    public func save(_ draft: SmartEditDraft, to url: URL) throws {
        try encode(draft).write(to: url, options: .atomic)
    }

    public func load(from url: URL) throws -> SmartEditDraft {
        try decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    private func validate(_ draft: SmartEditDraft) throws {
        guard draft.schemaVersion == SmartEditDraft.currentSchemaVersion else {
            throw SmartEditDraftError.unsupportedSchema
        }
        guard draft.engineConfiguration.selectedEngine == .local else {
            throw SmartEditDraftError.invalidDraft
        }
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.name.count <= 120,
              draft.sources.count <= 5_000,
              draft.clips.count <= 30_000,
              draft.audioSegments.count <= 30_000,
              !draft.speechLocaleIdentifier.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty,
              draft.activityTimeOffset.isFinite,
              Set(draft.sources.map(\.id)).count == draft.sources.count,
              Set(draft.clips.map(\.id)).count == draft.clips.count,
              Set(draft.audioSegments.map(\.id)).count == draft.audioSegments.count,
              draft.maximumHeight > 0,
              draft.durationSeconds.isFinite else {
            throw SmartEditDraftError.invalidDraft
        }
        let sourcesByID = Dictionary(uniqueKeysWithValues: draft.sources.map { ($0.id, $0) })
        for clip in draft.clips {
            guard let source = sourcesByID[clip.videoSourceID],
                  clip.videoStartSeconds.isFinite,
                  clip.videoEndSeconds.isFinite,
                  clip.timelineStartSeconds.isFinite,
                  clip.videoStartSeconds >= 0,
                  clip.timelineStartSeconds >= 0,
                  clip.videoEndSeconds > clip.videoStartSeconds,
                  clip.videoEndSeconds <= source.durationSeconds + 0.001,
                  clip.speechConfidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true else {
                throw SmartEditDraftError.invalidDraft
            }
        }
        for segment in draft.audioSegments {
            guard let source = sourcesByID[segment.sourceID],
                  source.hasAudio,
                  segment.sourceStartSeconds.isFinite,
                  segment.sourceEndSeconds.isFinite,
                  segment.timelineStartSeconds.isFinite,
                  segment.volume.isFinite,
                  (0...4).contains(segment.volume),
                  segment.sourceStartSeconds >= 0,
                  segment.timelineStartSeconds >= 0,
                  segment.sourceEndSeconds > segment.sourceStartSeconds,
                  segment.sourceEndSeconds <= source.durationSeconds + 0.001 else {
                throw SmartEditDraftError.invalidDraft
            }
        }
        for source in draft.sources {
            for cue in source.speechCues {
                guard cue.startSeconds.isFinite,
                      cue.endSeconds.isFinite,
                      cue.confidence.isFinite,
                      (0...1).contains(cue.confidence),
                      cue.startSeconds >= 0,
                      cue.endSeconds > cue.startSeconds,
                      cue.endSeconds <= source.durationSeconds + 0.001 else {
                    throw SmartEditDraftError.invalidDraft
                }
            }
        }
    }
}
