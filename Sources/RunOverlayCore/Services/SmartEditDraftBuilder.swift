import Foundation

public struct SmartEditKeptRange: Equatable, Sendable {
    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval

    public init(startSeconds: TimeInterval, endSeconds: TimeInterval) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

public enum SmartEditAutomaticCutReason: Equatable, Sendable {
    case speechProtected
    case classifiedSpeech
    case quietAudio
    case silentVideo
    case speechUncertain
}

/// 只计算本机分析后的建议，不创建草稿文件或启动视频导出。
public struct SmartEditAnalysisSummary: Equatable, Sendable {
    public struct Source: Equatable, Sendable {
        public let fileName: String
        public let durationSeconds: TimeInterval
        public let hasAudio: Bool
        public let speechRecognitionStatus: LocalSpeechRecognitionStatus
        public let speechCueCount: Int
        public let candidateBoundaryCount: Int
        public let proposedClipCount: Int
        public let proposedCutSeconds: [TimeInterval]
        public let keptRanges: [SmartEditKeptRange]
        public let keptDurationSeconds: TimeInterval
        public let removedDurationSeconds: TimeInterval
        public let automaticCutReason: SmartEditAutomaticCutReason
    }

    public let sources: [Source]
    public let totalDurationSeconds: TimeInterval
    public let outputDurationSeconds: TimeInterval
    public let removedDurationSeconds: TimeInterval
    public let proposedClipCount: Int

    public init(sources: [SmartEditMediaSource]) {
        let builder = SmartEditDraftBuilder()
        self.sources = sources.map { source in
            let clips = builder.automaticClips(for: source)
            let keptDuration = clips.reduce(0) { $0 + $1.durationSeconds }
            let reason: SmartEditAutomaticCutReason
            if !source.hasAudio {
                reason = .silentVideo
            } else if source.speechRecognitionStatus == .available,
                      !source.speechCues.isEmpty {
                reason = .speechProtected
            } else if !source.detectedSpeechRanges.isEmpty ||
                        !source.quietRanges.isEmpty {
                reason = source.detectedSpeechRanges.isEmpty ? .quietAudio : .classifiedSpeech
            } else {
                reason = .speechUncertain
            }
            return Source(
                fileName: source.fileName,
                durationSeconds: source.durationSeconds,
                hasAudio: source.hasAudio,
                speechRecognitionStatus: source.speechRecognitionStatus,
                speechCueCount: source.speechCues.count,
                candidateBoundaryCount: source.sceneBoundaries.count,
                proposedClipCount: clips.count,
                proposedCutSeconds: clips.dropLast().map(\.videoEndSeconds),
                keptRanges: clips.map {
                    SmartEditKeptRange(
                        startSeconds: $0.videoStartSeconds,
                        endSeconds: $0.videoEndSeconds
                    )
                },
                keptDurationSeconds: keptDuration,
                removedDurationSeconds: max(0, source.durationSeconds - keptDuration),
                automaticCutReason: reason
            )
        }
        totalDurationSeconds = self.sources.reduce(0) { $0 + $1.durationSeconds }
        outputDurationSeconds = self.sources.reduce(0) { $0 + $1.keptDurationSeconds }
        removedDurationSeconds = max(0, totalDurationSeconds - outputDurationSeconds)
        proposedClipCount = self.sources.reduce(0) { $0 + $1.proposedClipCount }
    }
}

/// 本机粗剪先保留每个源的完整原声，再将画面依镜头边界连续铺入视频轨。
public struct SmartEditDraftBuilder: Sendable {
    public init() {}

    public func clips(
        sourceID: UUID,
        duration: TimeInterval,
        sceneBoundaries: [TimeInterval],
        speechCues: [SmartEditSpeechCue],
        minimumShotDuration: TimeInterval = 1.2
    ) -> [SmartEditClip] {
        guard duration.isFinite, duration > 0 else { return [] }
        let safeDuration = duration
        let safeMinimum = minimumShotDuration.isFinite
            ? max(0.35, minimumShotDuration) : 1.2
        let protectedRanges = speechCues.compactMap { cue -> (Double, Double)? in
            guard cue.startSeconds.isFinite, cue.endSeconds.isFinite,
                  cue.endSeconds > cue.startSeconds else { return nil }
            let start = max(0, cue.startSeconds)
            let end = min(safeDuration, cue.endSeconds)
            return end > start ? (start, end) : nil
        }

        var boundaries = [0.0]
        for boundary in sceneBoundaries
        where boundary.isFinite && boundary > 0 && boundary < safeDuration {
            guard !protectedRanges.contains(where: {
                boundary > $0.0 && boundary < $0.1
            }) else { continue }
            if boundary - (boundaries.last ?? 0) >= safeMinimum {
                boundaries.append(boundary)
            }
        }
        if safeDuration - (boundaries.last ?? 0) < 0.2, boundaries.count > 1 {
            boundaries.removeLast()
        }
        boundaries.append(safeDuration)

        return zip(boundaries, boundaries.dropFirst()).compactMap { start, end in
            guard end - start >= 0.2 else { return nil }
            let spokenCues = speechCues.filter {
                let midpoint = ($0.startSeconds + $0.endSeconds) / 2
                return midpoint >= start && midpoint < end
            }
            let transcript = spokenCues.map(\.text).joined(separator: " ")
            return SmartEditClip(
                videoSourceID: sourceID,
                videoStartSeconds: start,
                videoEndSeconds: end,
                timelineStartSeconds: start,
                transcript: transcript,
                speechConfidence: spokenCues.isEmpty
                    ? nil
                    : spokenCues.reduce(0) { $0 + $1.confidence } /
                        Double(spokenCues.count),
                isLocked: false,
                keepsSourceAudio: false
            )
        }
    }

    /// 按画面素材的顺序拼接视频自带原声；无声素材对应的时间保持静音，不需要单独录音。
    public func audioSegments(
        sources: [SmartEditMediaSource]
    ) -> [SmartEditAudioSegment] {
        var timelineStart: TimeInterval = 0
        var segments: [SmartEditAudioSegment] = []
        for source in sources {
            defer { timelineStart += max(0, source.durationSeconds) }
            guard source.hasAudio,
                  source.durationSeconds.isFinite,
                  source.durationSeconds > 0 else { continue }
            segments.append(SmartEditAudioSegment(
                sourceID: source.id,
                sourceStartSeconds: 0,
                sourceEndSeconds: source.durationSeconds,
                timelineStartSeconds: timelineStart
            ))
        }
        return segments
    }

    /// 只裁确认无口播或足够安静的画面；语音识别失败不等于整段无声。
    public func automaticClips(for source: SmartEditMediaSource) -> [SmartEditClip] {
        guard source.durationSeconds.isFinite, source.durationSeconds > 0 else { return [] }
        let canSafelyCut = !source.hasAudio ||
            (source.speechRecognitionStatus == .available && !source.speechCues.isEmpty) ||
            !source.quietRanges.isEmpty ||
            !source.detectedSpeechRanges.isEmpty
        guard canSafelyCut else {
            return [SmartEditClip(
                videoSourceID: source.id,
                videoStartSeconds: 0,
                videoEndSeconds: source.durationSeconds
            )]
        }

        let candidates = clips(
            sourceID: source.id,
            duration: source.durationSeconds,
            sceneBoundaries: source.sceneBoundaries,
            speechCues: source.speechCues
        )
        return candidates.enumerated().flatMap { index, clip -> [SmartEditClip] in
            let speechRanges = source.speechRecognitionStatus == .available &&
                !source.speechCues.isEmpty
                ? source.speechCues.map {
                    SmartEditQuietRange(
                        startSeconds: $0.startSeconds,
                        endSeconds: $0.endSeconds
                    )
                }
                : source.detectedSpeechRanges
            let protected = speechRanges.compactMap { range -> SmartEditKeptRange? in
                let start = max(clip.videoStartSeconds, range.startSeconds - 0.25)
                let end = min(clip.videoEndSeconds, range.endSeconds + 0.25)
                guard start < end else { return nil }
                return SmartEditKeptRange(startSeconds: start, endSeconds: end)
            }.sorted { $0.startSeconds < $1.startSeconds }
            var intervals: [SmartEditKeptRange] = []
            for range in protected {
                if let last = intervals.last,
                   range.startSeconds <= last.endSeconds + 0.15 {
                    intervals[intervals.count - 1] = SmartEditKeptRange(
                        startSeconds: last.startSeconds,
                        endSeconds: max(last.endSeconds, range.endSeconds)
                    )
                } else {
                    intervals.append(range)
                }
            }
            var keep: [SmartEditKeptRange] = []
            var cursor = clip.videoStartSeconds
            for range in intervals {
                keep.append(contentsOf: condensedNonSpeech(
                    from: cursor,
                    to: range.startSeconds,
                    index: index,
                    total: candidates.count,
                    source: source
                ))
                keep.append(range)
                cursor = range.endSeconds
            }
            keep.append(contentsOf: condensedNonSpeech(
                from: cursor,
                to: clip.videoEndSeconds,
                index: index,
                total: candidates.count,
                source: source
            ))
            return keep.compactMap { range in
                guard range.endSeconds - range.startSeconds >= 0.1 else { return nil }
                var selected = clip
                selected.id = UUID()
                selected.videoStartSeconds = range.startSeconds
                selected.videoEndSeconds = range.endSeconds
                return selected
            }
        }
    }

    private func condensedNonSpeech(
        from start: TimeInterval,
        to end: TimeInterval,
        index: Int,
        total: Int,
        source: SmartEditMediaSource
    ) -> [SmartEditKeptRange] {
        let length = end - start
        guard length > 0.1 else { return [] }
        guard length > 2.4 else {
            return [SmartEditKeptRange(startSeconds: start, endSeconds: end)]
        }
        let knownQuiet = source.quietRanges.contains {
            $0.startSeconds <= start + 0.2 && $0.endSeconds >= end - 0.2
        }
        let canCut = !source.hasAudio ||
            (source.speechRecognitionStatus == .available && !source.speechCues.isEmpty) ||
            !source.detectedSpeechRanges.isEmpty ||
            knownQuiet
        guard canCut else {
            return [SmartEditKeptRange(startSeconds: start, endSeconds: end)]
        }
        let kept = min(2.5, max(1.2, length * 0.65))
        if index == 0 && abs(start) < 0.001 {
            return [SmartEditKeptRange(startSeconds: start, endSeconds: start + kept)]
        }
        if index == total - 1 && abs(end - source.durationSeconds) < 0.001 {
            return [SmartEditKeptRange(startSeconds: end - kept, endSeconds: end)]
        }
        let middle = (start + end) / 2
        return [SmartEditKeptRange(
            startSeconds: middle - kept / 2,
            endSeconds: middle + kept / 2
        )]
    }

    /// 每段视频的声音按同一入出点裁剪并按时间线拼接，不用单独录音或虚构口播。
    public func makeAutomaticDraft(
        name: String,
        sources: [SmartEditMediaSource],
        aspectRatio: ExportAspectRatio = .source,
        maximumHeight: Int = 1_080,
        speechLocaleIdentifier: String = "zh-CN",
        activitySamples: [ActivitySample] = [],
        activitySourceID: UUID? = nil,
        activityChannel: ActivitySource? = nil,
        activityTimeOffset: TimeInterval = 0,
        activityStartSnapshot: Date? = nil,
        videoTextLanguage: VideoTextLanguage = .chinese,
        overlayConfiguration: OverlayConfiguration = .preset(.runningFocus)
    ) -> SmartEditDraft {
        var draft = makeDraft(
            name: name,
            sources: sources,
            aspectRatio: aspectRatio,
            maximumHeight: maximumHeight,
            codec: .h264,
            speechLocaleIdentifier: speechLocaleIdentifier,
            activitySamples: activitySamples,
            activitySourceID: activitySourceID,
            activityChannel: activityChannel,
            activityTimeOffset: activityTimeOffset,
            activityStartSnapshot: activityStartSnapshot,
            videoTextLanguage: videoTextLanguage,
            overlayConfiguration: overlayConfiguration
        )
        var cursor: TimeInterval = 0
        var clips: [SmartEditClip] = []
        var audioSegments: [SmartEditAudioSegment] = []
        for source in sources {
            for var clip in automaticClips(for: source) {
                clip.timelineStartSeconds = cursor
                clips.append(clip)
                if source.hasAudio {
                    audioSegments.append(SmartEditAudioSegment(
                        sourceID: source.id,
                        sourceStartSeconds: clip.videoStartSeconds,
                        sourceEndSeconds: clip.videoEndSeconds,
                        timelineStartSeconds: cursor
                    ))
                }
                cursor += clip.durationSeconds
            }
        }
        draft.clips = clips
        draft.audioSegments = audioSegments
        return draft
    }

    public func makeDraft(
        name: String,
        sources: [SmartEditMediaSource],
        aspectRatio: ExportAspectRatio = .source,
        maximumHeight: Int = 1_080,
        codec: ExportSettings.Codec = .h264,
        speechLocaleIdentifier: String = "zh-CN",
        engineConfiguration: SmartEditEngineConfiguration = SmartEditEngineConfiguration(),
        activitySamples: [ActivitySample] = [],
        activitySourceID: UUID? = nil,
        activityChannel: ActivitySource? = nil,
        activityTimeOffset: TimeInterval = 0,
        activityStartSnapshot: Date? = nil,
        videoTextLanguage: VideoTextLanguage = .chinese,
        overlayConfiguration: OverlayConfiguration = .preset(.runningFocus)
    ) -> SmartEditDraft {
        let videoOrder = sources
        let audioSegments = audioSegments(sources: videoOrder)
        var timelineStart: TimeInterval = 0
        var videoClips: [SmartEditClip] = []
        for source in videoOrder {
            guard source.durationSeconds.isFinite, source.durationSeconds > 0 else {
                continue
            }
            let sourceClips = clips(
                sourceID: source.id,
                duration: source.durationSeconds,
                sceneBoundaries: source.sceneBoundaries,
                speechCues: source.speechCues
            ).map { clip in
                var clip = clip
                clip.timelineStartSeconds += timelineStart
                return clip
            }
            videoClips.append(contentsOf: sourceClips)
            timelineStart += max(0, source.durationSeconds)
        }
        videoClips.sort { $0.timelineStartSeconds < $1.timelineStartSeconds }
        return SmartEditDraft(
            name: name,
            sources: sources,
            clips: videoClips,
            audioSegments: audioSegments,
            aspectRatio: aspectRatio,
            maximumHeight: maximumHeight,
            codec: codec,
            speechLocaleIdentifier: speechLocaleIdentifier,
            engineConfiguration: engineConfiguration,
            activitySamples: activitySamples,
            activitySourceID: activitySourceID,
            activityChannel: activityChannel,
            activityTimeOffset: activityTimeOffset,
            activityStartSnapshot: activityStartSnapshot,
            videoTextLanguage: videoTextLanguage,
            overlayConfiguration: overlayConfiguration
        )
    }
}
