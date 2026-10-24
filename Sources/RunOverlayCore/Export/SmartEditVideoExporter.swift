@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

public enum SmartEditVideoExporterError: LocalizedError, Equatable {
    case emptyTimeline
    case invalidTimeline
    case missingSource(String)
    case missingVideoTrack(String)
    case missingAudioTrack(String)
    case outputAlreadyExists
    case cannotCreateSession
    case unsupportedOutputType
    case failed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .emptyTimeline:
            RunOverlayLocalization.text("smartEdit.export.empty")
        case .invalidTimeline:
            RunOverlayLocalization.text("smartEdit.export.invalidVideoTimeline")
        case let .missingSource(name):
            Self.message("smartEdit.export.sourceMissing", name)
        case let .missingVideoTrack(name):
            Self.message("smartEdit.export.videoTrackMissing", name)
        case let .missingAudioTrack(name):
            Self.message("smartEdit.export.audioTrackMissing", name)
        case .outputAlreadyExists:
            RunOverlayLocalization.text("smartEdit.export.outputExists")
        case .cannotCreateSession:
            RunOverlayLocalization.text("smartEdit.export.sessionFailure")
        case .unsupportedOutputType:
            RunOverlayLocalization.text("smartEdit.export.typeFailure")
        case let .failed(reason):
            Self.message("smartEdit.export.failed", reason)
        case .cancelled:
            RunOverlayLocalization.text("smartEdit.export.cancelled")
        }
    }

    private static func message(_ key: String, _ value: String) -> String {
        String(
            format: RunOverlayLocalization.text(key),
            locale: RunOverlayLocalization.locale,
            arguments: [value]
        )
    }
}

/// 合成源视频的画面与视频自带原声：音轨独立于画面切点，不需要另外录音。
@MainActor
public final class SmartEditVideoExporter {
    private var session: AVAssetExportSession?
    private var overlayExporter: VideoExporter?

    public init() {}

    public func export(
        _ draft: SmartEditDraft,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        guard !draft.clips.isEmpty else {
            throw SmartEditVideoExporterError.emptyTimeline
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw SmartEditVideoExporterError.outputAlreadyExists
        }
        let intermediateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunOverlay-SmartEdit-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: intermediateURL) }

        let sources = Dictionary(uniqueKeysWithValues: draft.sources.map { ($0.id, $0) })
        let assets = Dictionary(
            uniqueKeysWithValues: draft.sources.map { ($0.id, AVURLAsset(url: $0.fileURL)) }
        )
        let clips = draft.clips.sorted {
            $0.timelineStartSeconds < $1.timelineStartSeconds
        }
        guard Self.isContiguous(clips) else {
            throw SmartEditVideoExporterError.invalidTimeline
        }

        let composition = AVMutableComposition()
        guard let videoOutput = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw SmartEditVideoExporterError.cannotCreateSession
        }
        var previousVideoEnd: CMTime = .zero
        let timeScale: CMTimeScale = 60_000
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for (index, clip) in clips.enumerated() {
            try Task.checkCancellation()
            guard let source = sources[clip.videoSourceID],
                  let asset = assets[clip.videoSourceID] else {
                throw SmartEditVideoExporterError.missingSource("unknown")
            }
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw SmartEditVideoExporterError.missingVideoTrack(source.fileName)
            }
            let start = CMTime(seconds: clip.videoStartSeconds, preferredTimescale: timeScale)
            let sourceEnd = CMTime(seconds: clip.videoEndSeconds, preferredTimescale: timeScale)
            let duration = CMTimeSubtract(sourceEnd, start)
            let timelineStart = previousVideoEnd
            previousVideoEnd = CMTimeAdd(timelineStart, duration)
            try videoOutput.insertTimeRange(
                CMTimeRange(start: start, duration: duration),
                of: track,
                at: timelineStart
            )

            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let outputSize = Self.outputDimensions(
                draft: draft,
                source: source.dimensions
            )
            let transform = Self.fittedTransform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                renderSize: CGSize(width: outputSize.width, height: outputSize.height)
            )
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                assetTrack: videoOutput
            )
            layerInstruction.setTransform(transform, at: timelineStart)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: timelineStart, duration: duration)
            instruction.layerInstructions = [layerInstruction]
            instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
            instructions.append(instruction)
            await progress(0.15 * Double(index + 1) / Double(clips.count))
        }

        var audioMix: AVMutableAudioMix?
        if !draft.audioSegments.isEmpty {
            let segments = draft.audioSegments.sorted {
                $0.timelineStartSeconds < $1.timelineStartSeconds
            }
            guard Self.isValidAudio(
                segments,
                sources: sources,
                duration: draft.durationSeconds
            ) else {
                throw SmartEditVideoExporterError.invalidTimeline
            }
            guard let audioOutput = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw SmartEditVideoExporterError.cannotCreateSession
            }
            let parameters = AVMutableAudioMixInputParameters(track: audioOutput)
            var cursor: TimeInterval = 0

            for segment in segments {
                try Task.checkCancellation()
                guard let source = sources[segment.sourceID],
                      let asset = assets[segment.sourceID] else {
                    throw SmartEditVideoExporterError.missingSource("unknown")
                }
                guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                    throw SmartEditVideoExporterError.missingAudioTrack(source.fileName)
                }
                if segment.timelineStartSeconds > cursor + 0.001 {
                    let gap = segment.timelineStartSeconds - cursor
                    audioOutput.insertEmptyTimeRange(CMTimeRange(
                        start: CMTime(seconds: cursor, preferredTimescale: timeScale),
                        duration: CMTime(seconds: gap, preferredTimescale: timeScale)
                    ))
                    cursor += gap
                }
                guard abs(segment.timelineStartSeconds - cursor) <= 0.001 else {
                    throw SmartEditVideoExporterError.invalidTimeline
                }
                // 相机的音轨常比画面短几十毫秒。只截取真实音频，其余保持静音，
                // 否则 AVFoundation 会在拼接完整视频时以 -11841 中止导出。
                let trackRange = try await track.load(.timeRange)
                let audioStart = max(segment.sourceStartSeconds, trackRange.start.seconds)
                let audioEnd = min(segment.sourceEndSeconds, trackRange.end.seconds)
                let leadingSilence = min(
                    segment.durationSeconds,
                    max(0, audioStart - segment.sourceStartSeconds)
                )
                if leadingSilence > 0.000_01 {
                    audioOutput.insertEmptyTimeRange(CMTimeRange(
                        start: CMTime(seconds: cursor, preferredTimescale: timeScale),
                        duration: CMTime(
                            seconds: leadingSilence,
                            preferredTimescale: timeScale
                        )
                    ))
                    cursor += leadingSilence
                }
                let availableDuration = min(
                    max(0, audioEnd - audioStart),
                    max(0, segment.durationSeconds - leadingSilence)
                )
                if availableDuration > 0.000_01 {
                    let target = CMTime(seconds: cursor, preferredTimescale: timeScale)
                    try audioOutput.insertTimeRange(
                        CMTimeRange(
                            start: CMTime(seconds: audioStart, preferredTimescale: timeScale),
                            duration: CMTime(
                                seconds: availableDuration,
                                preferredTimescale: timeScale
                            )
                        ),
                        of: track,
                        at: target
                    )
                    parameters.setVolume(Float(segment.volume), at: target)
                    cursor += availableDuration
                }
                let trailingSilence = max(0, segment.timelineEndSeconds - cursor)
                if trailingSilence > 0.000_01 {
                    audioOutput.insertEmptyTimeRange(CMTimeRange(
                        start: CMTime(seconds: cursor, preferredTimescale: timeScale),
                        duration: CMTime(
                            seconds: trailingSilence,
                            preferredTimescale: timeScale
                        )
                    ))
                }
                cursor = segment.timelineEndSeconds
            }
            if cursor < draft.durationSeconds {
                audioOutput.insertEmptyTimeRange(CMTimeRange(
                    start: CMTime(seconds: cursor, preferredTimescale: timeScale),
                    duration: CMTime(
                        seconds: draft.durationSeconds - cursor,
                        preferredTimescale: timeScale
                    )
                ))
            }
            audioMix = AVMutableAudioMix()
            audioMix?.inputParameters = [parameters]
        }
        await progress(0.2)

        let firstSource = clips.first.flatMap { sources[$0.videoSourceID] }
            ?? draft.sources.first
        let outputDimensions = Self.outputDimensions(
            draft: draft,
            source: firstSource?.dimensions ?? PixelDimensions(width: 1920, height: 1080)
        )
        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.renderSize = CGSize(
            width: outputDimensions.width,
            height: outputDimensions.height
        )
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw SmartEditVideoExporterError.cannotCreateSession
        }
        let type: AVFileType = .mp4
        guard exportSession.supportedFileTypes.contains(type) else {
            throw SmartEditVideoExporterError.unsupportedOutputType
        }
        exportSession.videoComposition = videoComposition
        exportSession.audioMix = audioMix
        exportSession.shouldOptimizeForNetworkUse = true
        session = exportSession
        let monitor = Task {
            while !Task.isCancelled {
                await progress(0.2 + Double(exportSession.progress) * 0.4)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer {
            monitor.cancel()
            session = nil
        }

        do {
            try await withTaskCancellationHandler {
                try await Self.run(exportSession, to: intermediateURL, type: type)
            } onCancel: {
                Task { @MainActor [weak self] in self?.cancel() }
            }
        } catch {
            throw error
        }
        try Task.checkCancellation()
        await progress(0.6)
        let renderer = VideoExporter()
        overlayExporter = renderer
        defer { overlayExporter = nil }
        do {
            try await renderer.export(
                VideoExportRequest(
                    inputURL: intermediateURL,
                    outputURL: outputURL,
                    videoStart: nil,
                    timeOffset: 0,
                    overlay: draft.overlayConfiguration,
                    activitySamples: draft.activitySamples,
                    activityStart: draft.activityStartSnapshot ??
                        draft.activitySamples.first?.timestamp,
                    settings: ExportSettings(
                        codec: .h264,
                        maximumHeight: draft.maximumHeight,
                        aspectRatio: draft.aspectRatio,
                        videoTextLanguage: draft.videoTextLanguage
                    ),
                    smartEditOverlayTimeline: SmartEditOverlayTimeline(draft: draft)
                )
            ) { value in
                await progress(0.6 + value * 0.4)
            }
        } catch {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            throw error
        }
    }

    public func cancel() {
        session?.cancelExport()
        overlayExporter?.cancel()
    }

    public func makeJob(from draft: SmartEditDraft, exportDirectory: URL) throws -> SmartEditExportJob {
        guard !draft.clips.isEmpty else {
            throw SmartEditVideoExporterError.emptyTimeline
        }
        let base = Self.safeFileName(draft.name)
        var url = exportDirectory.appendingPathComponent("\(base).mp4")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = exportDirectory.appendingPathComponent("\(base)-\(suffix).mp4")
            suffix += 1
        }
        return SmartEditExportJob(draft: draft, outputURL: url)
    }

    private static func outputDimensions(
        draft: SmartEditDraft,
        source: PixelDimensions
    ) -> PixelDimensions {
        draft.aspectRatio.outputDimensions(source: source, shortEdge: draft.maximumHeight)
    }

    private static func fittedTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let points = [
            CGPoint.zero,
            CGPoint(x: naturalSize.width, y: 0),
            CGPoint(x: 0, y: naturalSize.height),
            CGPoint(x: naturalSize.width, y: naturalSize.height)
        ].map { $0.applying(preferredTransform) }
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? naturalSize.width
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? naturalSize.height
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        let scale = min(renderSize.width / width, renderSize.height / height)
        let transformedOrigin = CGPoint.zero.applying(preferredTransform)
        let offsetX = (renderSize.width - width * scale) / 2
        let offsetY = (renderSize.height - height * scale) / 2
        let originX = (transformedOrigin.x - minX) * scale + offsetX
        let originY = (transformedOrigin.y - minY) * scale + offsetY
        let origin = CGPoint(x: originX, y: originY)
        return CGAffineTransform(
            a: preferredTransform.a * scale,
            b: preferredTransform.b * scale,
            c: preferredTransform.c * scale,
            d: preferredTransform.d * scale,
            tx: origin.x,
            ty: origin.y
        )
    }

    private static func isContiguous(_ clips: [SmartEditClip]) -> Bool {
        var cursor = 0.0
        for clip in clips {
            guard clip.timelineStartSeconds.isFinite,
                  clip.durationSeconds > 0,
                  abs(clip.timelineStartSeconds - cursor) <= 0.001 else {
                return false
            }
            cursor += clip.durationSeconds
        }
        return cursor > 0
    }

    private static func hasContiguousVideoTimeline(_ clips: [SmartEditClip]) -> Bool {
        var end = 0.0
        for clip in clips {
            guard clip.timelineStartSeconds.isFinite,
                  abs(clip.timelineStartSeconds - end) <= 0.001,
                  clip.durationSeconds > 0 else { return false }
            end = clip.timelineEndSeconds
        }
        return end > 0
    }

    private static func isValidAudio(
        _ segments: [SmartEditAudioSegment],
        sources: [UUID: SmartEditMediaSource],
        duration: TimeInterval
    ) -> Bool {
        let ordered = segments.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
        var timelineCursor = 0.0
        var sourceCursor: [UUID: TimeInterval] = [:]
        for segment in ordered {
            guard let source = sources[segment.sourceID],
                  source.hasAudio,
                  segment.timelineStartSeconds.isFinite,
                  segment.timelineStartSeconds >= timelineCursor - 0.001,
                  segment.sourceStartSeconds.isFinite,
                  segment.sourceEndSeconds.isFinite,
                  segment.sourceStartSeconds >= (sourceCursor[source.id] ?? 0) - 0.001,
                  segment.sourceEndSeconds > segment.sourceStartSeconds,
                  segment.sourceEndSeconds <= source.durationSeconds + 0.001,
                  segment.timelineEndSeconds <= duration + 0.001,
                  (0...4).contains(segment.volume) else { return false }
            sourceCursor[source.id] = segment.sourceEndSeconds
            timelineCursor = segment.timelineEndSeconds
        }
        return true
    }

    private static func safeFileName(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.newlines)
        let name = value.components(separatedBy: forbidden)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "RunOverlay-SmartEdit" : name
    }

    private static func run(
        _ session: AVAssetExportSession,
        to url: URL,
        type: AVFileType
    ) async throws {
        let box = SmartEditExportSessionBox(session)
        try await withCheckedThrowingContinuation { continuation in
            session.outputURL = url
            session.outputFileType = type
            session.exportAsynchronously {
                switch box.session.status {
                case .completed: continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: SmartEditVideoExporterError.cancelled)
                case .failed:
                    continuation.resume(throwing: SmartEditVideoExporterError.failed(
                        box.session.error?.localizedDescription ?? "AVFoundation 导出失败"
                    ))
                default:
                    continuation.resume(throwing: SmartEditVideoExporterError.failed(
                        "AVFoundation 导出意外结束"
                    ))
                }
            }
        }
    }
}

public struct SmartEditExportJob: Sendable {
    public var draft: SmartEditDraft
    public var outputURL: URL
    public var progress: Double
    public var isComplete: Bool
    public var failureMessage: String?

    public init(
        draft: SmartEditDraft,
        outputURL: URL,
        progress: Double = 0,
        isComplete: Bool = false,
        failureMessage: String? = nil
    ) {
        self.draft = draft
        self.outputURL = outputURL
        self.progress = progress
        self.isComplete = isComplete
        self.failureMessage = failureMessage
    }
}

private final class SmartEditExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}
