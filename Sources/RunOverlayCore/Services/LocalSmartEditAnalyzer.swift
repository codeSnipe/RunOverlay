@preconcurrency import AVFoundation
import Foundation
import Speech
import SoundAnalysis
import Vision

public struct SmartEditSourceAnalysis: Sendable {
    public var source: SmartEditMediaSource
    public var message: String?

    public init(source: SmartEditMediaSource, message: String? = nil) {
        self.source = source
        self.message = message
    }
}

/// 首版所有抽帧和语音识别都留在 Mac 本机，不含任何网络请求路径。
public actor LocalSmartEditAnalyzer {
    private let speechRecognizer: SFSpeechRecognizer?
    private let featurePrintThreshold: Float
    private let speechAudioExtractor = LocalSpeechAudioExtractor()

    public init(
        locale: Locale = .current,
        featurePrintThreshold: Float = 0.38,
        recognizesSpeech: Bool = true
    ) {
        speechRecognizer = recognizesSpeech ? SFSpeechRecognizer(locale: locale) : nil
        self.featurePrintThreshold = featurePrintThreshold
    }

    public func analyze(
        fileURL: URL,
        originalVideoID: UUID? = nil,
        motionStartSnapshot: Date? = nil,
        motionOffsetSnapshot: TimeInterval? = nil,
        analyzesSpeech: Bool = true,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> SmartEditSourceAnalysis {
        let metadata = try await VideoMetadataReader().read(from: fileURL)
        let asset = AVURLAsset(url: fileURL)
        let boundaries = sceneBoundaries(
            asset: asset,
            duration: metadata.durationSeconds,
            progress: progress
        )
        if Task.isCancelled {
            throw CancellationError()
        }
        progress?(0.55)
        let quietRanges = metadata.hasAudio
            ? await quietAudioRanges(fileURL: fileURL, duration: metadata.durationSeconds)
            : []
        let detectedSpeechRanges = metadata.hasAudio
            ? await classifiedSpeechRanges(fileURL: fileURL, duration: metadata.durationSeconds)
            : []
        try Task.checkCancellation()
        let speech = analyzesSpeech
            ? try await recognizeSpeech(
                fileURL: fileURL,
                hasAudio: metadata.hasAudio,
                duration: metadata.durationSeconds
            )
            : (status: LocalSpeechRecognitionStatus.recognitionFailed,
               cues: [SmartEditSpeechCue](),
               message: String?.none)
        progress?(1)
        let bookmark = try? fileURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let source = SmartEditMediaSource(
            fileName: fileURL.lastPathComponent,
            fileURL: fileURL,
            bookmarkData: bookmark,
            originalVideoID: originalVideoID,
            motionStartSnapshot: motionStartSnapshot,
            motionOffsetSnapshot: motionOffsetSnapshot,
            durationSeconds: metadata.durationSeconds,
            dimensions: metadata.dimensions,
            capturedAt: metadata.capturedAt,
            hasAudio: metadata.hasAudio,
            sceneBoundaries: boundaries,
            quietRanges: quietRanges,
            detectedSpeechRanges: detectedSpeechRanges,
            speechRecognitionStatus: speech.status,
            speechCues: speech.cues
        )
        return SmartEditSourceAnalysis(source: source, message: speech.message)
    }

    private func classifiedSpeechRanges(
        fileURL: URL,
        duration: TimeInterval
    ) async -> [SmartEditQuietRange] {
        guard let request = try? SNClassifySoundRequest(
            classifierIdentifier: .version1
        ),
        let analyzer = try? SNAudioFileAnalyzer(url: fileURL) else { return [] }
        let observer = SmartEditSpeechClassificationObserver()
        do {
            try analyzer.add(request, withObserver: observer)
        } catch {
            return []
        }
        let completed = await withCheckedContinuation { continuation in
            analyzer.analyze { finished in
                continuation.resume(returning: finished)
            }
        }
        guard completed, !Task.isCancelled, observer.failure == nil else { return [] }
        return observer.ranges
            .filter { $0.endSeconds > $0.startSeconds }
            .map {
                SmartEditQuietRange(
                    startSeconds: max(0, $0.startSeconds),
                    endSeconds: min(duration, $0.endSeconds)
                )
            }
    }

    private func quietAudioRanges(
        fileURL: URL,
        duration: TimeInterval
    ) async -> [SmartEditQuietRange] {
        let asset = AVURLAsset(url: fileURL)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first
        else { return [] }
        guard let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }
        var activeStart: Double?
        var result: [SmartEditQuietRange] = []
        var lastEnd = 0.0
        let threshold: Float = 0.004
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                return []
            }
            let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            let length = CMSampleBufferGetDuration(buffer).seconds
            let end = length.isFinite && length > 0 ? time + length : time
            guard time.isFinite, let block = CMSampleBufferGetDataBuffer(buffer) else {
                continue
            }
            var raw = Data(count: CMBlockBufferGetDataLength(block))
            let status = raw.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(
                    block,
                    atOffset: 0,
                    dataLength: bytes.count,
                    destination: bytes.baseAddress!
                )
            }
            guard status == noErr else { continue }
            let isQuiet = raw.withUnsafeBytes { bytes in
                let samples = bytes.bindMemory(to: Float.self)
                guard !samples.isEmpty else { return false }
                var peak: Float = 0
                for value in samples {
                    peak = max(peak, abs(value))
                    if peak > threshold { return false }
                }
                return true
            }
            if isQuiet {
                if activeStart == nil { activeStart = time }
            } else if let start = activeStart {
                if time - start >= 1.1 {
                    result.append(SmartEditQuietRange(
                        startSeconds: max(0, start),
                        endSeconds: min(duration, time)
                    ))
                }
                activeStart = nil
            }
            lastEnd = max(lastEnd, end)
        }
        guard reader.status == .completed else { return [] }
        if let start = activeStart, lastEnd - start >= 1.1 {
            result.append(SmartEditQuietRange(
                startSeconds: max(0, start),
                endSeconds: min(duration, lastEnd)
            ))
        }
        return result
    }

    private func sceneBoundaries(
        asset: AVURLAsset,
        duration: TimeInterval,
        progress: (@Sendable (Double) -> Void)?
    ) -> [TimeInterval] {
        guard duration > 2 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)

        var previous: VNFeaturePrintObservation?
        var candidates: [Double] = []
        let sampleTimes = stride(from: 1.0, to: duration, by: 3.0)
        let totalSamples = max(Int((duration - 1) / 3) + 1, 1)
        for (index, second) in sampleTimes.enumerated() {
            progress?(min(Double(index + 1) / Double(totalSamples) * 0.55, 0.55))
            if withUnsafeCurrentTask(body: { $0?.isCancelled ?? false }) {
                break
            }
            guard let image = try? generator.copyCGImage(
                at: CMTime(seconds: second, preferredTimescale: 600),
                actualTime: nil
            ) else {
                continue
            }
            let request = VNGenerateImageFeaturePrintRequest()
            request.imageCropAndScaleOption = .centerCrop
            guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil,
                  let current = request.results?.first as? VNFeaturePrintObservation else {
                continue
            }
            if let previous {
                var distance: Float = 0
                let succeeded = (try? current.computeDistance(&distance, to: previous)) != nil
                if succeeded, distance >= featurePrintThreshold,
                   candidates.last.map({ second - $0 >= 2.2 }) ?? true {
                    candidates.append(second)
                }
            }
            previous = current
        }

        return candidates
    }

    private func recognizeSpeech(
        fileURL: URL,
        hasAudio: Bool,
        duration: TimeInterval
    ) async throws -> (
        status: LocalSpeechRecognitionStatus,
        cues: [SmartEditSpeechCue],
        message: String?
    ) {
        guard hasAudio else {
            return (.noAudio, [], nil)
        }
        guard let speechRecognizer else {
            return (
                .onDeviceUnavailable,
                [],
                RunOverlayLocalization.text("smartEdit.speech.localeUnavailable")
            )
        }
        guard speechRecognizer.supportsOnDeviceRecognition else {
            return (
                .onDeviceUnavailable,
                [],
                RunOverlayLocalization.text("smartEdit.speech.onDeviceUnavailable")
            )
        }

        let authorization = await authorizationStatus()
        guard authorization == .authorized else {
            let status: LocalSpeechRecognitionStatus = authorization == .denied
                ? .permissionDenied : .recognitionFailed
            return (
                status,
                [],
                RunOverlayLocalization.text(
                    authorization == .denied
                        ? "smartEdit.speech.permissionDenied"
                        : "smartEdit.speech.permissionRequired"
                )
            )
        }

        let chunkDuration: TimeInterval = 45
        let overlap: TimeInterval = 1
        var cues: [SmartEditSpeechCue] = []
        var chunkStart: TimeInterval = 0
        while chunkStart < duration {
            try Task.checkCancellation()
            let length = min(chunkDuration, duration - chunkStart)
            let recognitionAudioURL: URL
            do {
                recognitionAudioURL = try await speechAudioExtractor.extractM4A(
                    from: fileURL,
                    start: chunkStart,
                    duration: length
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return (
                    .recognitionFailed,
                    cues,
                    RunOverlayLocalization.text("smartEdit.speech.failed")
                )
            }
            defer { try? FileManager.default.removeItem(at: recognitionAudioURL) }
            let request = SFSpeechURLRecognitionRequest(url: recognitionAudioURL)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false
            request.addsPunctuation = true

            do {
                let box = LocalSpeechContinuationBox()
                let chunkCues = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation {
                        (continuation: CheckedContinuation<[SmartEditSpeechCue], Error>) in
                        box.install(continuation)
                        let task = speechRecognizer.recognitionTask(with: request) { result, error in
                            if let error {
                                box.complete(.failure(error))
                            } else if let result, result.isFinal {
                                let values = result.bestTranscription.segments.compactMap {
                                    segment -> SmartEditSpeechCue? in
                                    let start = chunkStart + segment.timestamp
                                    let end = start + segment.duration
                                    let midpoint = (start + end) / 2
                                    guard segment.duration > 0,
                                          midpoint >= (chunkStart == 0 ? 0 : chunkStart + overlap),
                                          !segment.substring.trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                          ).isEmpty else { return nil }
                                    return SmartEditSpeechCue(
                                        startSeconds: start,
                                        endSeconds: min(duration, end),
                                        text: segment.substring,
                                        confidence: Double(segment.confidence)
                                    )
                                }
                                box.complete(.success(values))
                            }
                        }
                        box.install(task)
                    }
                } onCancel: {
                    box.cancel()
                }
                cues.append(contentsOf: chunkCues)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return (
                    .recognitionFailed,
                    cues,
                    RunOverlayLocalization.text("smartEdit.speech.failed")
                )
            }
            if chunkStart + length >= duration { break }
            chunkStart += chunkDuration - overlap
        }
        return (.available, cues, nil)
    }

    private func authorizationStatus() async -> SFSpeechRecognizerAuthorizationStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return SFSpeechRecognizer.authorizationStatus()
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        @unknown default:
            return .restricted
        }
    }
}

private final class SmartEditSpeechClassificationObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var classifiedRanges: [SmartEditQuietRange] = []
    private var classificationFailure: Error?

    var ranges: [SmartEditQuietRange] {
        lock.lock()
        defer { lock.unlock() }
        return classifiedRanges
    }

    var failure: Error? {
        lock.lock()
        defer { lock.unlock() }
        return classificationFailure
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult,
              let speech = result.classification(forIdentifier: "speech"),
              result.classifications.first?.identifier == "speech",
              speech.confidence >= 0.75 else { return }
        let range = result.timeRange
        guard range.start.seconds.isFinite, range.end.seconds.isFinite else { return }
        lock.lock()
        classifiedRanges.append(SmartEditQuietRange(
            startSeconds: range.start.seconds,
            endSeconds: range.end.seconds
        ))
        lock.unlock()
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        lock.lock()
        classificationFailure = error
        lock.unlock()
    }
}

@MainActor
private final class LocalSpeechAudioExtractor {
    func extractM4A(
        from fileURL: URL,
        start: TimeInterval,
        duration: TimeInterval
    ) async throws -> URL {
        let asset = AVURLAsset(url: fileURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let composition = AVMutableComposition()
        guard let sourceTrack = audioTracks.first,
              let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw LocalSpeechAudioExtractionError.missingAudio
        }
        try compositionTrack.insertTimeRange(
            CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 60_000),
                duration: CMTime(seconds: duration, preferredTimescale: 60_000)
            ),
            of: sourceTrack,
            at: .zero
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunOverlay-Speech-\(UUID().uuidString).m4a")
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw LocalSpeechAudioExtractionError.cannotCreateExport
        }
        guard session.supportedFileTypes.contains(AVFileType.m4a) else {
            throw LocalSpeechAudioExtractionError.unsupportedExport
        }
        let sessionBox = LocalSpeechExportSessionBox(session)
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    session.outputURL = outputURL
                    session.outputFileType = AVFileType.m4a
                    session.exportAsynchronously {
                        switch sessionBox.session.status {
                        case .completed:
                            continuation.resume()
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        case .failed:
                            continuation.resume(
                                throwing: sessionBox.session.error ??
                                    LocalSpeechAudioExtractionError.exportFailed
                            )
                        default:
                            continuation.resume(
                                throwing: LocalSpeechAudioExtractionError.exportFailed
                            )
                        }
                    }
                }
            } onCancel: {
                Task { @MainActor in sessionBox.cancel() }
            }
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}

private enum LocalSpeechAudioExtractionError: Error {
    case missingAudio
    case cannotCreateExport
    case unsupportedExport
    case exportFailed
}

private final class LocalSpeechExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }

    @MainActor
    func cancel() {
        session.cancelExport()
    }
}

private final class LocalSpeechContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[SmartEditSpeechCue], Error>?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isCompleted = false

    func install(_ continuation: CheckedContinuation<[SmartEditSpeechCue], Error>) {
        lock.lock()
        self.continuation = continuation
        let shouldCancel = isCompleted
        lock.unlock()
        if shouldCancel {
            continuation.resume(throwing: CancellationError())
        }
    }

    func install(_ recognitionTask: SFSpeechRecognitionTask) {
        lock.lock()
        self.recognitionTask = recognitionTask
        let shouldCancel = isCompleted
        lock.unlock()
        if shouldCancel {
            recognitionTask.cancel()
        }
    }

    func cancel() {
        lock.lock()
        isCompleted = true
        let task = recognitionTask
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        task?.cancel()
        continuation?.resume(throwing: CancellationError())
    }

    func complete(_ result: Result<[SmartEditSpeechCue], Error>) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        isCompleted = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return }
        continuation.resume(with: result)
    }
}
