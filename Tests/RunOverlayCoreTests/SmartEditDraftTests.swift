import Foundation
import RunOverlayCore
import XCTest

final class SmartEditDraftTests: XCTestCase {
    func test智能剪辑数据图层遵循原视频时间和各视频图层配置() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let firstID = UUID()
        let secondID = UUID()
        var firstOverlay = OverlayConfiguration.preset(.runningFocus)
        firstOverlay.elements = [try XCTUnwrap(
            firstOverlay.elements.first(where: { $0.kind == .clockTime })
        )]
        var secondOverlay = OverlayConfiguration.preset(.minimal)
        secondOverlay.elements = [try XCTUnwrap(
            secondOverlay.elements.first(where: { $0.kind == .distance })
        )]
        let first = SmartEditMediaSource(
            id: firstID,
            fileName: "第一段.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/第一段.mp4"),
            motionStartSnapshot: base,
            motionOffsetSnapshot: 0.5,
            overlayConfigurationSnapshot: firstOverlay,
            durationSeconds: 14,
            dimensions: PixelDimensions(width: 1920, height: 1080),
            hasAudio: true
        )
        let second = SmartEditMediaSource(
            id: secondID,
            fileName: "第二段.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/第二段.mp4"),
            motionStartSnapshot: base.addingTimeInterval(100),
            motionOffsetSnapshot: -1,
            overlayConfigurationSnapshot: secondOverlay,
            durationSeconds: 8,
            dimensions: PixelDimensions(width: 1920, height: 1080),
            hasAudio: true
        )
        let draft = SmartEditDraft(
            name: "剪辑数据时间映射",
            sources: [first, second],
            clips: [
                SmartEditClip(
                    videoSourceID: firstID,
                    videoStartSeconds: 2,
                    videoEndSeconds: 4,
                    timelineStartSeconds: 0
                ),
                SmartEditClip(
                    videoSourceID: firstID,
                    videoStartSeconds: 10,
                    videoEndSeconds: 12,
                    timelineStartSeconds: 2
                ),
                SmartEditClip(
                    videoSourceID: secondID,
                    videoStartSeconds: 3,
                    videoEndSeconds: 5,
                    timelineStartSeconds: 4
                )
            ],
            activityTimeOffset: 0.25,
            overlayConfiguration: .preset(.sport)
        )
        let restored = try SmartEditDraftCodec().decode(
            SmartEditDraftCodec().encode(draft)
        )
        let timeline = SmartEditOverlayTimeline(draft: restored)
        let beginning = try XCTUnwrap(timeline.frame(at: 0.5))
        let afterCut = try XCTUnwrap(timeline.frame(at: 2.5))
        let secondCamera = try XCTUnwrap(timeline.frame(at: 4.5))

        XCTAssertEqual(beginning.sourceSeconds, 2.5, accuracy: 0.0001)
        XCTAssertEqual(
            try XCTUnwrap(beginning.clockTime).timeIntervalSince(base),
            3.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(beginning.configuration, firstOverlay)
        XCTAssertEqual(afterCut.sourceSeconds, 10.5, accuracy: 0.0001)
        XCTAssertEqual(
            try XCTUnwrap(afterCut.clockTime).timeIntervalSince(base),
            11.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(secondCamera.sourceID, secondID)
        XCTAssertEqual(
            try XCTUnwrap(secondCamera.clockTime).timeIntervalSince(base),
            102.75,
            accuracy: 0.0001
        )
        XCTAssertEqual(secondCamera.configuration, secondOverlay)
        XCTAssertNil(timeline.frame(at: 6.1))
    }

    func test剪辑图层进度使用原视频运动时间而不是成片进度() throws {
        let activityStart = Date(timeIntervalSince1970: 1_800_000_000)
        let capturedAt = activityStart.addingTimeInterval(10)
        let sourceID = UUID()
        let source = SmartEditMediaSource(
            id: sourceID,
            fileName: "进度测试.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/progress.mp4"),
            motionStartSnapshot: capturedAt,
            durationSeconds: 30,
            dimensions: PixelDimensions(width: 1920, height: 1080),
            hasAudio: false
        )
        let samples = stride(from: 0, through: 40, by: 1).map { second in
            ActivitySample(
                timestamp: activityStart.addingTimeInterval(Double(second)),
                distanceMeters: Double(second) * 100
            )
        }
        let draft = SmartEditDraft(
            name: "原始运动进度映射",
            sources: [source],
            clips: [
                SmartEditClip(
                    videoSourceID: sourceID,
                    videoStartSeconds: 20,
                    videoEndSeconds: 30,
                    timelineStartSeconds: 0
                )
            ],
            activitySamples: samples,
            activityStartSnapshot: activityStart
        )

        let early = try XCTUnwrap(SmartEditOverlayTimeline(draft: draft).frame(at: 1))
        let late = try XCTUnwrap(SmartEditOverlayTimeline(draft: draft).frame(at: 9))
        XCTAssertEqual(try XCTUnwrap(early.clockTime), activityStart.addingTimeInterval(31))
        XCTAssertEqual(
            try XCTUnwrap(early.activityProgress?.currentDistanceMeters ?? nil),
            3_100,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(late.activityProgress?.currentDistanceMeters ?? nil),
            3_900,
            accuracy: 0.001
        )
    }

    func test本机分析说明按真实候选切点和口播计算草稿数量() {
        let source = SmartEditMediaSource(
            fileName: "跑步口播.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/跑步口播.mp4"),
            durationSeconds: 12,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            hasAudio: true,
            sceneBoundaries: [3, 6, 9],
            speechRecognitionStatus: .available,
            speechCues: [
                SmartEditSpeechCue(
                    startSeconds: 2.5,
                    endSeconds: 3.5,
                    text: "继续跑",
                    confidence: 0.9
                )
            ]
        )
        let silent = SmartEditMediaSource(
            fileName: "静音镜头.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/静音镜头.mp4"),
            durationSeconds: 4,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            hasAudio: false,
            speechRecognitionStatus: .noAudio
        )

        let summary = SmartEditAnalysisSummary(sources: [source, silent])
        let draft = SmartEditDraftBuilder().makeAutomaticDraft(
            name: "仅确认后创建",
            sources: [source, silent]
        )

        XCTAssertEqual(summary.totalDurationSeconds, 16)
        XCTAssertEqual(summary.sources.map(\.candidateBoundaryCount), [3, 0])
        XCTAssertEqual(summary.sources.map(\.speechCueCount), [1, 0])
        XCTAssertEqual(summary.sources.map(\.proposedClipCount), [5, 1])
        XCTAssertEqual(summary.sources[0].proposedCutSeconds, [2.25, 3.75, 6, 8.475])
        XCTAssertTrue(summary.sources[1].proposedCutSeconds.isEmpty)
        XCTAssertEqual(summary.proposedClipCount, draft.clips.count)
        XCTAssertEqual(draft.audioSegments.count, summary.sources[0].proposedClipCount)
    }

    func test自动剪辑真正删除非口播画面且原声按同区间拼接() throws {
        let source = SmartEditMediaSource(
            fileName: "Vlog.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/vlog.mp4"),
            durationSeconds: 18,
            dimensions: PixelDimensions(width: 1920, height: 1080),
            hasAudio: true,
            sceneBoundaries: [6, 12],
            speechRecognitionStatus: .available,
            speechCues: [
                SmartEditSpeechCue(
                    startSeconds: 7,
                    endSeconds: 10,
                    text: "我正在跑步",
                    confidence: 0.91
                )
            ]
        )
        let builder = SmartEditDraftBuilder()
        let summary = SmartEditAnalysisSummary(sources: [source])
        let draft = builder.makeAutomaticDraft(name: "自动成片", sources: [source])

        XCTAssertLessThan(draft.durationSeconds, source.durationSeconds)
        XCTAssertEqual(summary.outputDurationSeconds, draft.durationSeconds, accuracy: 0.001)
        XCTAssertEqual(summary.removedDurationSeconds,
                       source.durationSeconds - draft.durationSeconds, accuracy: 0.001)
        XCTAssertTrue(draft.clips.contains {
            $0.videoStartSeconds <= 7 && $0.videoEndSeconds >= 10
        })
        XCTAssertEqual(draft.audioSegments.count, draft.clips.count)
        for (clip, audio) in zip(draft.clips, draft.audioSegments) {
            XCTAssertEqual(clip.videoStartSeconds, audio.sourceStartSeconds, accuracy: 0.001)
            XCTAssertEqual(clip.videoEndSeconds, audio.sourceEndSeconds, accuracy: 0.001)
            XCTAssertEqual(clip.timelineStartSeconds, audio.timelineStartSeconds, accuracy: 0.001)
        }
        XCTAssertNoThrow(try SmartEditDraftCodec().encode(draft))
    }

    func test语音识别不可用时不误删口播() {
        let source = SmartEditMediaSource(
            fileName: "未知讲话.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/unknown.mp4"),
            durationSeconds: 12,
            dimensions: PixelDimensions(width: 1920, height: 1080),
            hasAudio: true,
            sceneBoundaries: [3, 6, 9],
            speechRecognitionStatus: .permissionDenied
        )
        let draft = SmartEditDraftBuilder().makeAutomaticDraft(
            name: "保守成片",
            sources: [source]
        )
        XCTAssertEqual(draft.clips.count, 1)
        XCTAssertEqual(draft.durationSeconds, 12)
        XCTAssertEqual(draft.audioSegments.first?.sourceEndSeconds, 12)
    }

    func test语音识别失败时只裁确认安静的镜头() throws {
        let source = SmartEditMediaSource(
            fileName: "静音与口播混合.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/mixed.mp4"),
            durationSeconds: 12,
            dimensions: PixelDimensions(width: 1920, height: 1080),
            hasAudio: true,
            sceneBoundaries: [4, 8],
            quietRanges: [SmartEditQuietRange(startSeconds: 0, endSeconds: 4)],
            speechRecognitionStatus: .recognitionFailed
        )
        let summary = SmartEditAnalysisSummary(sources: [source])
        let draft = SmartEditDraftBuilder().makeAutomaticDraft(
            name: "安全回退",
            sources: [source]
        )

        XCTAssertEqual(summary.sources[0].automaticCutReason, .quietAudio)
        XCTAssertLessThan(draft.clips[0].durationSeconds, 4)
        XCTAssertEqual(draft.clips[1].videoStartSeconds, 4)
        XCTAssertEqual(draft.clips[1].videoEndSeconds, 8)
        XCTAssertEqual(draft.clips[2].videoStartSeconds, 8)
        XCTAssertEqual(draft.clips[2].videoEndSeconds, 12)
        XCTAssertEqual(draft.audioSegments.map(\.sourceStartSeconds),
                       draft.clips.map(\.videoStartSeconds))
        XCTAssertEqual(summary.outputDurationSeconds, draft.durationSeconds, accuracy: 0.001)
        XCTAssertNoThrow(try SmartEditDraftCodec().encode(draft))
    }

    func test主工作台同名视频在草稿中保留独立来源与时间校准() throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstTime = Date(timeIntervalSince1970: 1_800_000_000)
        let secondTime = Date(timeIntervalSince1970: 1_800_000_100)
        let first = SmartEditMediaSource(
            fileName: "VID_001.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/camera-a/VID_001.mp4"),
            originalVideoID: firstID,
            motionStartSnapshot: firstTime,
            motionOffsetSnapshot: 1.25,
            durationSeconds: 5,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            capturedAt: firstTime,
            hasAudio: true
        )
        let second = SmartEditMediaSource(
            fileName: "VID_001.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/camera-b/VID_001.mp4"),
            originalVideoID: secondID,
            motionStartSnapshot: secondTime,
            motionOffsetSnapshot: -0.5,
            durationSeconds: 8,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            capturedAt: secondTime,
            hasAudio: true
        )

        let draft = SmartEditDraftBuilder().makeDraft(
            name: "项目视频",
            sources: [first, second]
        )
        let restored = try SmartEditDraftCodec().decode(
            SmartEditDraftCodec().encode(draft)
        )

        XCTAssertEqual(restored.sources.map(\.originalVideoID), [firstID, secondID])
        XCTAssertEqual(restored.sources.map(\.motionStartSnapshot), [firstTime, secondTime])
        XCTAssertEqual(restored.sources.map(\.motionOffsetSnapshot), [1.25, -0.5])
        XCTAssertEqual(restored.clips.map(\.videoSourceID), [first.id, second.id])
        XCTAssertEqual(restored.audioSegments.map(\.sourceID), [first.id, second.id])
        XCTAssertEqual(restored.audioSegments.map(\.timelineStartSeconds), [0, 5])
    }

    func testDraftBuilderKeepsAudioContinuousAcrossPictureCuts() throws {
        let sourceID = UUID()
        let source = SmartEditMediaSource(
            id: sourceID,
            fileName: "run.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/run.mp4"),
            durationSeconds: 30,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            hasAudio: true,
            sceneBoundaries: [5, 10, 15],
            speechCues: [
                SmartEditSpeechCue(
                    startSeconds: 4,
                    endSeconds: 7,
                    text: "这里有上坡",
                    confidence: 0.91
                )
            ]
        )

        let draft = SmartEditDraftBuilder().makeDraft(
            name: "跑步 Vlog",
            sources: [source]
        )

        XCTAssertEqual(draft.clips.count, 3)
        XCTAssertFalse(draft.clips.contains(where: \.keepsSourceAudio))
        XCTAssertEqual(draft.audioSegments.count, 1)
        XCTAssertEqual(draft.audioSegments.first?.sourceStartSeconds, 0)
        XCTAssertEqual(draft.audioSegments.first?.sourceEndSeconds, 30)
        XCTAssertEqual(draft.audioSegments.first?.timelineStartSeconds, 0)
        XCTAssertEqual(draft.preservedSpeechCueCount, 1)
        XCTAssertEqual(draft.clips[0].videoEndSeconds, 10)
        XCTAssertFalse(draft.clips[0].isLocked)
        XCTAssertEqual(draft.clips[0].transcript, "这里有上坡")
        XCTAssertTrue(source.speechCues[0].isLocked)
    }

    func testAudioTrackAddsSilenceForSourceWithoutAudio() {
        let first = SmartEditMediaSource(
            fileName: "silent.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/silent.mp4"),
            durationSeconds: 12,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            hasAudio: false
        )
        let second = SmartEditMediaSource(
            fileName: "voice.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/voice.mp4"),
            durationSeconds: 8,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            hasAudio: true
        )

        let segments = SmartEditDraftBuilder().audioSegments(sources: [first, second])

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].sourceID, second.id)
        XCTAssertEqual(segments[0].timelineStartSeconds, 12)
        XCTAssertEqual(segments[0].sourceEndSeconds, 8)
    }

    func test视频自带原声与画面顺序一致且无声段保留静音() throws {
        let later = SmartEditMediaSource(
            fileName: "后导入.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/later.mp4"),
            durationSeconds: 6,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_100),
            hasAudio: true
        )
        let silent = SmartEditMediaSource(
            fileName: "无声.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/silent.mp4"),
            durationSeconds: 4,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_050),
            hasAudio: false
        )
        let earlier = SmartEditMediaSource(
            fileName: "先导入.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/earlier.mp4"),
            durationSeconds: 5,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            hasAudio: true
        )

        let draft = SmartEditDraftBuilder().makeDraft(
            name: "视频原声",
            sources: [later, silent, earlier]
        )
        let restored = try SmartEditDraftCodec().decode(
            SmartEditDraftCodec().encode(draft)
        )

        XCTAssertEqual(restored.clips.map(\.videoSourceID), [later.id, silent.id, earlier.id])
        XCTAssertEqual(restored.clips.map(\.timelineStartSeconds), [0, 6, 10])
        XCTAssertEqual(restored.audioSegments.map(\.sourceID), [later.id, earlier.id])
        XCTAssertEqual(restored.audioSegments.map(\.timelineStartSeconds), [0, 10])
        XCTAssertEqual(restored.audioSegments.map(\.sourceStartSeconds), [0, 0])
        XCTAssertEqual(restored.audioSegments.map(\.sourceEndSeconds), [6, 5])
        XCTAssertEqual(restored.durationSeconds, 15)
    }

    func testDraftCodecRoundTripsIndependentTracks() throws {
        let activitySourceID = UUID()
        let source = SmartEditMediaSource(
            fileName: "voice.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/voice.mp4"),
            durationSeconds: 10,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            hasAudio: true
        )
        let draft = SmartEditDraftBuilder().makeDraft(
            name: "口播保留",
            sources: [source],
            activitySourceID: activitySourceID,
            activityStartSnapshot: Date(timeIntervalSince1970: 1_800_000_000),
            videoTextLanguage: .english
        )

        let decoded = try SmartEditDraftCodec().decode(
            SmartEditDraftCodec().encode(draft)
        )

        XCTAssertEqual(decoded, draft)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.activitySourceID, activitySourceID)
        XCTAssertEqual(decoded.videoTextLanguage, .english)
    }

    func testDraftCodecRejectsAudioBeyondSourceDuration() throws {
        let source = SmartEditMediaSource(
            fileName: "voice.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/voice.mp4"),
            durationSeconds: 10,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            hasAudio: true
        )
        var draft = SmartEditDraft(name: "无效草稿", sources: [source])
        draft.audioSegments = [
            SmartEditAudioSegment(
                sourceID: source.id,
                sourceStartSeconds: 0,
                sourceEndSeconds: 11,
                timelineStartSeconds: 0
            )
        ]

        XCTAssertThrowsError(try SmartEditDraftCodec().encode(draft)) { error in
            XCTAssertEqual(error as? SmartEditDraftError, .invalidDraft)
        }
    }

    func test草稿只保存模型密钥钥匙串定位不保存密钥正文() throws {
        let model = SmartEditModelConfiguration(
            provider: "aliyun-bailian",
            baseURL: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1"),
            modelID: "qwen3-vl-plus",
            region: "中国大陆"
        )
        let draft = SmartEditDraft(
            name: "模型预留",
            engineConfiguration: SmartEditEngineConfiguration(model: model)
        )

        let json = try XCTUnwrap(
            String(data: SmartEditDraftCodec().encode(draft), encoding: .utf8)
        )
        XCTAssertFalse(json.contains(model.keychainAccount))
        XCTAssertTrue(json.contains(model.modelID))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("apiKey"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("secret"))
    }

    func testMovingPictureClipDoesNotMoveOrTrimVoiceTrack() throws {
        let first = SmartEditMediaSource(
            fileName: "first.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/first.mp4"),
            durationSeconds: 12,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            hasAudio: true,
            sceneBoundaries: [4, 8],
            speechCues: [
                SmartEditSpeechCue(
                    startSeconds: 1,
                    endSeconds: 2,
                    text: "起跑",
                    confidence: 0.9
                )
            ]
        )
        let second = SmartEditMediaSource(
            fileName: "second.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/second.mp4"),
            durationSeconds: 8,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            hasAudio: true
        )
        let draft = SmartEditDraftBuilder().makeDraft(
            name: "同一来源重排画面",
            sources: [first]
        )
        let originalAudio = draft.audioSegments
        let middleClip = try XCTUnwrap(draft.clips.dropFirst().first)

        let moved = try XCTUnwrap(
            SmartEditTimelineEditor().movingClip(middleClip.id, by: 1, in: draft)
        )

        XCTAssertEqual(moved.audioSegments, originalAudio)
        XCTAssertEqual(moved.audioSegments.count, originalAudio.count)
        XCTAssertEqual(moved.preservedSpeechCueCount, 1)
        XCTAssertEqual(moved.clips[1].videoSourceID, first.id)
        XCTAssertEqual(moved.clips[1].id, draft.clips[2].id)
        XCTAssertEqual(moved.clips[1].videoStartSeconds, 8)
        XCTAssertEqual(moved.clips[1].timelineStartSeconds, 4)
        XCTAssertEqual(moved.clips[2].id, draft.clips[1].id)
        XCTAssertEqual(moved.clips[2].videoSourceID, first.id)
        XCTAssertEqual(moved.clips[2].videoStartSeconds, 4)
        XCTAssertEqual(moved.clips[2].timelineStartSeconds, 8)
        XCTAssertNil(moved.clips.first(where: { $0.videoSourceID == second.id }))
        XCTAssertEqual(moved.clips.first?.timelineStartSeconds, 0)
        XCTAssertNil(
            SmartEditTimelineEditor().movingClip(
                moved.clips[0].id,
                by: -1,
                in: moved
            )
        )
    }

    func testAdjustingPictureInOutMovesLaterPictureButNeverAudio() throws {
        let source = SmartEditMediaSource(
            fileName: "run.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/run.mp4"),
            durationSeconds: 30,
            dimensions: PixelDimensions(width: 1_920, height: 1_080),
            hasAudio: true,
            sceneBoundaries: [10, 20]
        )
        let draft = SmartEditDraftBuilder().makeDraft(
            name: "调整画面入出点",
            sources: [source]
        )
        let audioBefore = draft.audioSegments
        let firstClip = try XCTUnwrap(draft.clips.first)

        let adjusted = try XCTUnwrap(
            SmartEditTimelineEditor().updatingClipRange(
                firstClip.id,
                startSeconds: 1,
                endSeconds: 12,
                in: draft
            )
        )

        XCTAssertEqual(adjusted.clips[0].videoStartSeconds, 1)
        XCTAssertEqual(adjusted.clips[0].videoEndSeconds, 12)
        XCTAssertEqual(adjusted.clips[1].timelineStartSeconds, 11)
        XCTAssertEqual(adjusted.audioSegments, audioBefore)
        XCTAssertNil(
            SmartEditTimelineEditor().updatingClipRange(
                firstClip.id,
                startSeconds: 2,
                endSeconds: 31,
                in: draft
            )
        )
    }

    func testLegacyDraftMigratesToIndependentVoiceTrackWithoutDeletingSpeech() throws {
        let sourceID = UUID()
        let firstClipID = UUID()
        let secondClipID = UUID()
        let legacyJSON: [String: Any] = [
            "schemaVersion": 1,
            "id": UUID().uuidString,
            "name": "旧剪辑草稿",
            "createdAt": 1_800_000_000,
            "updatedAt": 1_800_000_000,
            "sources": [[
                "id": sourceID.uuidString,
                "fileName": "voice.mp4",
                "fileURL": URL(fileURLWithPath: "/tmp/voice.mp4").absoluteString,
                "durationSeconds": 10,
                "dimensions": ["width": 1920, "height": 1080],
                "hasAudio": true,
                "sceneBoundaries": [],
                "speechRecognitionStatus": "available",
                "speechCues": [[
                    "id": UUID().uuidString,
                    "startSeconds": 0.5,
                    "endSeconds": 1.2,
                    "text": "旧版语音",
                    "confidence": 0.89
                ]]
            ]],
            "clips": [
                [
                    "id": firstClipID.uuidString,
                    "videoSourceID": sourceID.uuidString,
                    "videoStartSeconds": 0,
                    "videoEndSeconds": 4,
                    "audioSourceID": sourceID.uuidString,
                    "audioStartSeconds": 0,
                    "audioEndSeconds": 4,
                    "transcript": "向前跑",
                    "speechConfidence": 0.91,
                    "isLocked": true,
                    "keepsSourceAudio": true
                ],
                [
                    "id": secondClipID.uuidString,
                    "videoSourceID": sourceID.uuidString,
                    "videoStartSeconds": 4,
                    "videoEndSeconds": 8,
                    "audioSourceID": sourceID.uuidString,
                    "audioStartSeconds": 4,
                    "audioEndSeconds": 8,
                    "transcript": "到达坡道",
                    "speechConfidence": 0.87,
                    "isLocked": true,
                    "keepsSourceAudio": true
                ]
            ],
            "aspectRatio": "landscape16x9",
            "maximumHeight": 1080,
            "codec": "h264"
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyJSON)

        let migrated = try SmartEditDraftCodec().decode(data)

        XCTAssertEqual(migrated.schemaVersion, SmartEditDraft.currentSchemaVersion)
        XCTAssertEqual(migrated.clips.map(\.transcript), ["向前跑", "到达坡道"])
        XCTAssertEqual(migrated.audioSegments.count, 1)
        XCTAssertEqual(migrated.audioSegments.first?.sourceStartSeconds, 0)
        XCTAssertEqual(migrated.audioSegments.first?.sourceEndSeconds, 8)
        XCTAssertEqual(migrated.audioSegments.first?.timelineStartSeconds, 0)
    }
}
