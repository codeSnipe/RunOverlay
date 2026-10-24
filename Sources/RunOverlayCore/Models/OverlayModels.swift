import Foundation

public enum OverlayTemplatePreset: String, CaseIterable, Codable, Hashable, Sendable {
    // 新建项目使用独立模板，避免改变已保存项目中旧「运动」模板的渲染。
    case runningFocus
    case minimal
    case sport
    case technology
    case track
    case finishLine
    case trail
    case nightRun
    case stadiumLive

    public var displayName: String {
        switch self {
        case .runningFocus: RunOverlayLocalization.text("template.runningFocus")
        case .minimal: RunOverlayLocalization.text("template.minimal")
        case .sport: RunOverlayLocalization.text("template.sport")
        case .technology: RunOverlayLocalization.text("template.technology")
        case .track: RunOverlayLocalization.text("template.track")
        case .finishLine: RunOverlayLocalization.text("template.finishLine")
        case .trail: RunOverlayLocalization.text("template.trail")
        case .nightRun: RunOverlayLocalization.text("template.nightRun")
        case .stadiumLive: RunOverlayLocalization.text("template.stadiumLive")
        }
    }

    public var defaultBackgroundOpacity: Double {
        switch self {
        case .runningFocus: 0
        case .minimal: 0.2
        case .sport: 0.56
        case .technology: 0.7
        case .track: 0.58
        case .finishLine: 0.46
        case .trail: 0.62
        case .nightRun: 0.68
        case .stadiumLive: 0
        }
    }
}

public enum OverlayElementKind: String, CaseIterable, Codable, Hashable, Sendable {
    case pace
    case distance
    case elapsedTime
    case clockTime
    case heartRate
    case cadence
    case power
    case altitude
    case ascent
    case calories
    case route
    case progress
    case elevationProfile

    public static let cardOrder: [OverlayElementKind] = [
        .route, .progress, .elevationProfile, .ascent,
        .pace, .calories, .heartRate, .altitude,
        .distance, .clockTime, .elapsedTime, .cadence,
        .power
    ]

    public var displayName: String {
        switch self {
        case .pace: RunOverlayLocalization.text("overlay.pace")
        case .distance: RunOverlayLocalization.text("overlay.distance")
        case .elapsedTime: RunOverlayLocalization.text("overlay.elapsedTime")
        case .clockTime: RunOverlayLocalization.text("overlay.clockTime")
        case .heartRate: RunOverlayLocalization.text("overlay.heartRate")
        case .cadence: RunOverlayLocalization.text("overlay.cadence")
        case .power: RunOverlayLocalization.text("overlay.power")
        case .altitude: RunOverlayLocalization.text("overlay.altitude")
        case .ascent: RunOverlayLocalization.text("overlay.ascent")
        case .calories: RunOverlayLocalization.text("overlay.calories")
        case .route: RunOverlayLocalization.text("overlay.route")
        case .progress: RunOverlayLocalization.text("overlay.progress")
        case .elevationProfile: RunOverlayLocalization.text("overlay.elevationProfile")
        }
    }

    public var supportedMeasurementUnits: [OverlayMeasurementUnit] {
        switch self {
        case .pace, .distance: [.kilometers, .miles]
        case .altitude, .ascent, .elevationProfile: [.meters, .feet]
        default: []
        }
    }

    public var defaultMeasurementUnit: OverlayMeasurementUnit? {
        supportedMeasurementUnits.first
    }
}

public enum OverlayMeasurementUnit: String, Codable, Hashable, Sendable {
    case kilometers
    case miles
    case meters
    case feet

    public var symbol: String {
        switch self {
        case .kilometers: "km"
        case .miles: "mi"
        case .meters: "m"
        case .feet: "ft"
        }
    }

    public var metersPerUnit: Double {
        switch self {
        case .kilometers: 1_000
        case .miles: 1_609.344
        case .meters: 1
        case .feet: 0.3048
        }
    }
}

public enum OverlayClockDisplay: String, CaseIterable, Codable, Hashable, Sendable {
    case dateTime
    case date
    case time
}

public enum OverlayDurationDisplay: String, CaseIterable, Codable, Hashable, Sendable {
    case adaptive
    case hoursMinutesSeconds
}

public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct OverlayElementConfiguration: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: OverlayElementKind
    public var frame: NormalizedRect
    public var isVisible: Bool
    public var opacity: Double
    public var backgroundOpacity: Double?
    public var textScale: Double
    public var measurementUnit: OverlayMeasurementUnit?
    public var clockDisplay: OverlayClockDisplay
    public var durationDisplay: OverlayDurationDisplay

    public var effectiveMeasurementUnit: OverlayMeasurementUnit? {
        measurementUnit ?? kind.defaultMeasurementUnit
    }

    public init(
        id: UUID = UUID(),
        kind: OverlayElementKind,
        frame: NormalizedRect,
        isVisible: Bool = true,
        opacity: Double = 1,
        backgroundOpacity: Double? = nil,
        textScale: Double = 1,
        measurementUnit: OverlayMeasurementUnit? = nil,
        clockDisplay: OverlayClockDisplay = .dateTime,
        durationDisplay: OverlayDurationDisplay = .adaptive
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.isVisible = isVisible
        self.opacity = opacity
        self.backgroundOpacity = backgroundOpacity
        self.textScale = textScale
        self.measurementUnit = measurementUnit
        self.clockDisplay = clockDisplay
        self.durationDisplay = durationDisplay
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case frame
        case isVisible
        case opacity
        case backgroundOpacity
        case textScale
        case measurementUnit
        case clockDisplay
        case durationDisplay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(OverlayElementKind.self, forKey: .kind)
        frame = try container.decode(NormalizedRect.self, forKey: .frame)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        opacity = try container.decode(Double.self, forKey: .opacity)
        backgroundOpacity = try container.decodeIfPresent(
            Double.self,
            forKey: .backgroundOpacity
        )
        textScale = try container.decodeIfPresent(Double.self, forKey: .textScale) ?? 1
        measurementUnit = try container.decodeIfPresent(
            OverlayMeasurementUnit.self,
            forKey: .measurementUnit
        )
        clockDisplay = try container.decodeIfPresent(
            OverlayClockDisplay.self,
            forKey: .clockDisplay
        ) ?? .dateTime
        durationDisplay = try container.decodeIfPresent(
            OverlayDurationDisplay.self,
            forKey: .durationDisplay
        ) ?? .adaptive
    }
}

public struct OverlayConfiguration: Codable, Hashable, Sendable {
    public var preset: OverlayTemplatePreset
    public var accentHex: String
    public var foregroundHex: String
    public var elements: [OverlayElementConfiguration]

    public init(
        preset: OverlayTemplatePreset,
        accentHex: String,
        foregroundHex: String,
        elements: [OverlayElementConfiguration]
    ) {
        self.preset = preset
        self.accentHex = accentHex
        self.foregroundHex = foregroundHex
        self.elements = elements
    }

    public func newElement(for kind: OverlayElementKind) -> OverlayElementConfiguration {
        let templateFrame = Self.preset(preset).elements
            .first(where: { $0.kind == kind })?.frame
        let width = kind == .elevationProfile
            ? 0.30
            : kind == .route
            ? 0.22
            : kind == .progress
                ? 0.30
                : kind == .clockTime ? 0.28 : 0.19
        let height = kind == .elevationProfile
            ? 0.18 : kind == .route ? 0.22 : kind == .progress ? 0.06 : 0.10
        let preferred = templateFrame ?? NormalizedRect(
            x: kind == .elevationProfile ? 0.67
                : kind == .clockTime ? 0.68 : kind == .progress ? 0.04 : 0.76,
            y: kind == .elevationProfile ? 0.19
                : kind == .route ? 0.06 : kind == .progress ? 0.82 : 0.19,
            width: width,
            height: height
        )
        let xPositions = kind == .elevationProfile
            ? [0.67, 0.36, 0.04]
            : kind == .route
            ? [0.04, 0.38, 0.72]
            : kind == .progress
                ? [0.04, 0.36, 0.68]
            : kind == .clockTime
                ? [0.68, 0.36, 0.04]
                : [0.76, 0.52, 0.28, 0.04]
        let yPositions = kind == .elevationProfile
            ? [0.19, 0.38, 0.57, 0.76, 0.05]
            : kind == .route
            ? [0.06, 0.31, 0.56, 0.76]
            : kind == .progress
                ? [0.82, 0.72, 0.62, 0.52, 0.42, 0.32, 0.22, 0.12]
                : [0.19, 0.31, 0.43, 0.55, 0.67, 0.79, 0.07]

        for frame in [preferred] + yPositions.flatMap({ y in
            xPositions.map { x in
                NormalizedRect(x: x, y: y, width: width, height: height)
            }
        }) {
            guard frame.x >= 0, frame.y >= 0,
                  frame.x + frame.width <= 1,
                  frame.y + frame.height <= 1,
                  !elements.contains(where: { Self.overlaps(frame, $0.frame) }) else {
                continue
            }
            return OverlayElementConfiguration(
                kind: kind,
                frame: frame,
                backgroundOpacity: kind == .elevationProfile ? 0.32 : nil
            )
        }
        return OverlayElementConfiguration(
            kind: kind,
            frame: preferred,
            backgroundOpacity: kind == .elevationProfile ? 0.32 : nil
        )
    }

    private static func overlaps(_ first: NormalizedRect, _ second: NormalizedRect) -> Bool {
        let gap = 0.01
        return first.x < second.x + second.width + gap &&
            first.x + first.width + gap > second.x &&
            first.y < second.y + second.height + gap &&
            first.y + first.height + gap > second.y
    }

    public static func preset(_ preset: OverlayTemplatePreset) -> Self {
        switch preset {
        case .runningFocus:
            return Self(
                preset: preset,
                accentHex: "#FFFFFF",
                foregroundHex: "#FFFFFF",
                elements: [
                    element(.route, x: 0.025, y: 0.05, width: 0.225, height: 0.18),
                    OverlayElementConfiguration(
                        kind: .distance,
                        frame: NormalizedRect(x: 0.015, y: 0.26, width: 0.24, height: 0.11),
                        textScale: 0.88
                    ),
                    OverlayElementConfiguration(
                        kind: .pace,
                        frame: NormalizedRect(x: 0.015, y: 0.40, width: 0.24, height: 0.11),
                        textScale: 0.88
                    ),
                    OverlayElementConfiguration(
                        kind: .elapsedTime,
                        frame: NormalizedRect(x: 0.015, y: 0.54, width: 0.24, height: 0.11),
                        textScale: 0.88,
                        durationDisplay: .hoursMinutesSeconds
                    ),
                    OverlayElementConfiguration(
                        kind: .heartRate,
                        frame: NormalizedRect(x: 0.015, y: 0.68, width: 0.24, height: 0.11),
                        textScale: 0.88
                    ),
                    OverlayElementConfiguration(
                        kind: .progress,
                        frame: NormalizedRect(x: 0.32, y: 0.05, width: 0.36, height: 0.12),
                        backgroundOpacity: 0.35
                    ),
                    OverlayElementConfiguration(
                        kind: .clockTime,
                        frame: NormalizedRect(x: 0.73, y: 0.87, width: 0.26, height: 0.08),
                        textScale: 1.1,
                        clockDisplay: .dateTime
                    )
                ]
            )
        case .minimal:
            return Self(
                preset: preset,
                accentHex: "#FFFFFF",
                foregroundHex: "#FFFFFF",
                elements: [
                    element(.route, x: 0.04, y: 0.06, width: 0.22, height: 0.22),
                    element(.pace, x: 0.04, y: 0.31, width: 0.16, height: 0.09),
                    element(.heartRate, x: 0.04, y: 0.42, width: 0.14, height: 0.09),
                    element(.distance, x: 0.04, y: 0.53, width: 0.16, height: 0.09),
                    clockTimeElement()
                ]
            )
        case .sport:
            return Self(
                preset: preset,
                accentHex: "#D7FF3F",
                foregroundHex: "#FFFFFF",
                elements: [
                    element(.route, x: 0.04, y: 0.06, width: 0.22, height: 0.22),
                    element(.pace, x: 0.04, y: 0.31, width: 0.17, height: 0.10),
                    element(.heartRate, x: 0.04, y: 0.43, width: 0.15, height: 0.10),
                    element(.distance, x: 0.04, y: 0.55, width: 0.17, height: 0.10),
                    clockTimeElement()
                ]
            )
        case .technology:
            return Self(
                preset: preset,
                accentHex: "#55E6FF",
                foregroundHex: "#F4FAFF",
                elements: [
                    element(.route, x: 0.04, y: 0.06, width: 0.22, height: 0.22),
                    element(.pace, x: 0.04, y: 0.31, width: 0.17, height: 0.10),
                    element(.heartRate, x: 0.04, y: 0.43, width: 0.15, height: 0.10),
                    element(.distance, x: 0.04, y: 0.55, width: 0.17, height: 0.10),
                    clockTimeElement()
                ]
            )
        case .track:
            return Self(
                preset: preset,
                accentHex: "#FFAD72",
                foregroundHex: "#FFF8F0",
                elements: [
                    element(.ascent, x: 0.04, y: 0.05, width: 0.15, height: 0.09),
                    element(.calories, x: 0.21, y: 0.05, width: 0.17, height: 0.09),
                    element(.clockTime, x: 0.40, y: 0.05, width: 0.56, height: 0.09),
                    element(.pace, x: 0.04, y: 0.70, width: 0.30, height: 0.12),
                    element(.distance, x: 0.36, y: 0.70, width: 0.30, height: 0.12),
                    element(.heartRate, x: 0.04, y: 0.84, width: 0.30, height: 0.11),
                    element(.elapsedTime, x: 0.36, y: 0.84, width: 0.30, height: 0.11),
                    element(.route, x: 0.72, y: 0.70, width: 0.24, height: 0.25)
                ]
            )
        case .finishLine:
            return Self(
                preset: preset,
                accentHex: "#EFD77E",
                foregroundHex: "#FFFDF4",
                elements: [
                    element(.route, x: 0.04, y: 0.05, width: 0.23, height: 0.20),
                    element(.clockTime, x: 0.35, y: 0.05, width: 0.61, height: 0.09),
                    element(.distance, x: 0.04, y: 0.68, width: 0.44, height: 0.14),
                    element(.pace, x: 0.04, y: 0.84, width: 0.23, height: 0.11),
                    element(.elapsedTime, x: 0.29, y: 0.84, width: 0.26, height: 0.11),
                    element(.heartRate, x: 0.64, y: 0.69, width: 0.32, height: 0.10),
                    element(.calories, x: 0.64, y: 0.82, width: 0.32, height: 0.13)
                ]
            )
        case .trail:
            return Self(
                preset: preset,
                accentHex: "#B9D99B",
                foregroundHex: "#F5FAF1",
                elements: [
                    element(.route, x: 0.04, y: 0.06, width: 0.23, height: 0.23),
                    element(.clockTime, x: 0.35, y: 0.05, width: 0.61, height: 0.09),
                    element(.altitude, x: 0.04, y: 0.32, width: 0.20, height: 0.10),
                    element(.pace, x: 0.04, y: 0.45, width: 0.20, height: 0.10),
                    element(.ascent, x: 0.04, y: 0.69, width: 0.42, height: 0.12),
                    element(.calories, x: 0.50, y: 0.69, width: 0.46, height: 0.12),
                    element(.distance, x: 0.04, y: 0.84, width: 0.42, height: 0.11),
                    element(.heartRate, x: 0.50, y: 0.84, width: 0.46, height: 0.11)
                ]
            )
        case .nightRun:
            return Self(
                preset: preset,
                accentHex: "#88D9C0",
                foregroundHex: "#F2F9F6",
                elements: [
                    element(.clockTime, x: 0.04, y: 0.05, width: 0.62, height: 0.09),
                    element(.calories, x: 0.04, y: 0.54, width: 0.30, height: 0.10),
                    element(.pace, x: 0.04, y: 0.68, width: 0.30, height: 0.12),
                    element(.distance, x: 0.36, y: 0.68, width: 0.30, height: 0.12),
                    element(.heartRate, x: 0.04, y: 0.83, width: 0.30, height: 0.12),
                    element(.cadence, x: 0.36, y: 0.83, width: 0.30, height: 0.12),
                    element(.route, x: 0.70, y: 0.69, width: 0.26, height: 0.26)
                ]
            )
        case .stadiumLive:
            return Self(
                preset: preset,
                accentHex: "#FFFFFF",
                foregroundHex: "#FFFFFF",
                elements: [
                    OverlayElementConfiguration(
                        kind: .route,
                        frame: NormalizedRect(x: 0.03, y: 0.08, width: 0.20, height: 0.23),
                        backgroundOpacity: 0.52
                    ),
                    element(.pace, x: 0.03, y: 0.61, width: 0.26, height: 0.10),
                    element(.calories, x: 0.03, y: 0.73, width: 0.30, height: 0.10),
                    element(.heartRate, x: 0.03, y: 0.85, width: 0.25, height: 0.13),
                    element(.altitude, x: 0.72, y: 0.72, width: 0.25, height: 0.09),
                    element(.distance, x: 0.68, y: 0.81, width: 0.29, height: 0.09),
                    element(.clockTime, x: 0.50, y: 0.91, width: 0.47, height: 0.07)
                ]
            )
        }
    }

    private static func element(
        _ kind: OverlayElementKind,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> OverlayElementConfiguration {
        OverlayElementConfiguration(
            kind: kind,
            frame: NormalizedRect(x: x, y: y, width: width, height: height)
        )
    }

    public static func clockTimeElement() -> OverlayElementConfiguration {
        OverlayElementConfiguration(
            kind: .clockTime,
            frame: NormalizedRect(x: 0.68, y: 0.06, width: 0.28, height: 0.10)
        )
    }
}
