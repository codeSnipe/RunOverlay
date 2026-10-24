@preconcurrency import AVFoundation
import CoreImage
import Foundation

public struct VideoExportRequest: Sendable {
    public var inputURL: URL
    public var outputURL: URL
    public var videoStart: Date?
    public var timeOffset: TimeInterval
    public var overlay: OverlayConfiguration
    public var activitySamples: [ActivitySample]
    public var activityStart: Date?
    public var settings: ExportSettings
    public var rotation: VideoRotation
    public var smartEditOverlayTimeline: SmartEditOverlayTimeline?

    public init(
        inputURL: URL,
        outputURL: URL,
        videoStart: Date?,
        timeOffset: TimeInterval,
        overlay: OverlayConfiguration,
        activitySamples: [ActivitySample],
        activityStart: Date?,
        settings: ExportSettings,
        rotation: VideoRotation = .none,
        smartEditOverlayTimeline: SmartEditOverlayTimeline? = nil
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.videoStart = videoStart
        self.timeOffset = timeOffset
        self.overlay = overlay
        self.activitySamples = activitySamples
        self.activityStart = activityStart
        self.settings = settings
        self.rotation = rotation
        self.smartEditOverlayTimeline = smartEditOverlayTimeline
    }
}

public enum VideoExporterError: LocalizedError, Equatable {
    case cannotCreateSession
    case unsupportedOutputType
    case outputAlreadyExists
    case failed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .cannotCreateSession:
            RunOverlayLocalization.text("error.cannotCreateExport")
        case .unsupportedOutputType:
            RunOverlayLocalization.text("error.unsupportedOutput")
        case .outputAlreadyExists:
            RunOverlayLocalization.text("error.outputExists")
        case let .failed(message):
            String(
                format: RunOverlayLocalization.text("error.exportFailed"),
                locale: RunOverlayLocalization.locale,
                arguments: [message]
            )
        case .cancelled:
            RunOverlayLocalization.text("error.cancelled")
        }
    }
}

@MainActor
public final class VideoExporter {
    private var activeSession: AVAssetExportSession?

    public init() {}

    public func export(
        _ request: VideoExportRequest,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        guard !FileManager.default.fileExists(atPath: request.outputURL.path) else {
            throw VideoExporterError.outputAlreadyExists
        }

        let asset = AVURLAsset(url: request.inputURL)
        _ = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoExporterError.cannotCreateSession
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let displayedSourceSize = naturalSize.applying(preferredTransform)
        let sourceDimensions = PixelDimensions(
            width: max(1, Int(abs(displayedSourceSize.width).rounded())),
            height: max(1, Int(abs(displayedSourceSize.height).rounded()))
        )
        let outputDimensions = request.settings.aspectRatio.outputDimensions(
            source: request.rotation.dimensions(afterRotating: sourceDimensions),
            shortEdge: request.settings.maximumHeight
        )
        let renderSize = CGSize(
            width: outputDimensions.width,
            height: outputDimensions.height
        )
        let timeline = ActivityTimeline()
        let activityProgressCalculator = ActivityProgressCalculator(
            samples: request.activitySamples
        )
        let renderer = OverlayFrameRenderer()
        let route = request.activitySamples.compactMap(\.coordinate)
        let elevationProfile = ElevationProfile(samples: request.activitySamples)
        let videoComposition = AVMutableVideoComposition(
            asset: asset
        ) { frameRequest in
            let seconds = frameRequest.compositionTime.seconds
            let editFrame = request.smartEditOverlayTimeline?.frame(at: seconds)
            let timestamp = editFrame?.clockTime ?? request.videoStart?.addingTimeInterval(
                request.timeOffset + seconds
            )
            let sample = editFrame?.activitySample ?? timestamp.flatMap {
                timeline.sample(at: $0, in: request.activitySamples)
            }
            let original = frameRequest.sourceImage
            let transformedSource = VideoFrameTransform.fitted(
                VideoFrameTransform.rotated(original, by: request.rotation),
                renderSize: renderSize
            )
            let extent = CGRect(origin: .zero, size: renderSize)
            let background = CIImage(color: .black).cropped(to: extent)
            let source = transformedSource
                .composited(over: background)
                .cropped(to: extent)
            let size = renderSize

            if let overlay = renderer.render(
                size: size,
                configuration: editFrame?.configuration ?? request.overlay,
                sample: sample,
                activityProgress: editFrame?.activityProgress ??
                    activityProgressCalculator.progress(for: sample),
                route: editFrame?.route ?? route,
                elevationProfile: editFrame?.elevationProfile ?? elevationProfile,
                activityStart: request.activityStart,
                clockTime: timestamp,
                videoTextLanguage: request.settings.videoTextLanguage
            ) {
                frameRequest.finish(
                    with: overlay
                        .composited(over: source)
                        .cropped(to: extent),
                    context: nil
                )
            } else {
                frameRequest.finish(
                    with: source,
                    context: nil
                )
            }
        }
        videoComposition.renderSize = renderSize
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let preset = request.settings.codec == .hevc
            ? AVAssetExportPresetHEVCHighestQuality
            : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw VideoExporterError.cannotCreateSession
        }

        let fileType: AVFileType = request.settings.codec == .hevc ? .mov : .mp4
        guard session.supportedFileTypes.contains(fileType) else {
            throw VideoExporterError.unsupportedOutputType
        }

        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        session.allowsParallelizedExport = true
        setActiveSession(session)

        let progressTask = Task {
            while !Task.isCancelled {
                await progress(Double(session.progress))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        defer {
            progressTask.cancel()
            setActiveSession(nil)
        }

        do {
            try await withTaskCancellationHandler {
                try await export(
                    session: session,
                    to: request.outputURL,
                    as: fileType
                )
                await progress(1)
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancel()
                }
            }
        } catch {
            if FileManager.default.fileExists(atPath: request.outputURL.path) {
                try? FileManager.default.removeItem(at: request.outputURL)
            }
            throw error
        }
    }

    public func cancel() {
        activeSession?.cancelExport()
    }

    private func setActiveSession(_ session: AVAssetExportSession?) {
        activeSession = session
    }

    private func export(
        session: AVAssetExportSession,
        to outputURL: URL,
        as fileType: AVFileType
    ) async throws {
        let sessionBox = ExportSessionBox(session: session)
        try await withCheckedThrowingContinuation { continuation in
            session.outputURL = outputURL
            session.outputFileType = fileType
            session.exportAsynchronously {
                Task { @MainActor in
                    switch sessionBox.session.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: VideoExporterError.cancelled)
                    case .failed:
                        continuation.resume(
                            throwing: VideoExporterError.failed(
                                sessionBox.session.error?.localizedDescription ??
                                    RunOverlayLocalization.text("error.unknown")
                            )
                        )
                    default:
                        continuation.resume(
                            throwing: VideoExporterError.failed(
                                RunOverlayLocalization.text("error.unexpectedExportEnd")
                            )
                        )
                    }
                }
            }
        }
    }
}

@MainActor
private final class ExportSessionBox {
    let session: AVAssetExportSession

    init(session: AVAssetExportSession) {
        self.session = session
    }
}
