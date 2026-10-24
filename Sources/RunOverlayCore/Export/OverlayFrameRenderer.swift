import CoreGraphics
import CoreImage
import CoreText
import Foundation

public struct OverlayFrameRenderer: Sendable {
    private enum FontWeight: Sendable {
        case medium
        case semibold
        case bold

        var postScriptName: String {
            switch self {
            case .medium: "PingFangSC-Medium"
            case .semibold: "PingFangSC-Semibold"
            case .bold: "PingFangSC-Bold"
            }
        }
    }

    public init() {}

    public func render(
        size: CGSize,
        configuration: OverlayConfiguration,
        sample: ActivitySample?,
        activityProgress: ActivityProgress? = nil,
        route: [GeoCoordinate],
        elevationProfile: ElevationProfile? = nil,
        activityStart: Date?,
        clockTime: Date? = nil,
        videoTextLanguage: VideoTextLanguage = .chinese
    ) -> CIImage? {
        guard
            sample != nil || configuration.elements.contains(where: {
                $0.kind == .clockTime && $0.isVisible
            }),
            size.width > 0,
            size.height > 0,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: Int(size.width.rounded()),
                height: Int(size.height.rounded()),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        let accent = color(from: configuration.accentHex)
        let foreground = color(from: configuration.foregroundHex)

        for element in configuration.elements where element.isVisible {
            guard sample != nil || element.kind == .clockTime else {
                continue
            }
            context.saveGState()
            let rect = renderRect(element.frame, size: size)
            let elementOpacity = min(max(element.opacity, 0), 1)
            let backgroundOpacity = min(
                max(
                    element.backgroundOpacity ??
                        configuration.preset.defaultBackgroundOpacity,
                    0
                ),
                1
            )
            context.saveGState()
            context.setAlpha(CGFloat(elementOpacity * backgroundOpacity))
            drawBackground(
                in: rect,
                preset: configuration.preset,
                kind: element.kind,
                accent: accent,
                context: context
            )
            context.restoreGState()
            context.setAlpha(elementOpacity)
            if configuration.preset == .runningFocus && element.kind != .progress {
                context.setShadow(
                    offset: CGSize(width: 0, height: -2),
                    blur: 4,
                    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.72)
                )
            }

            if element.kind == .progress {
                drawProgress(
                    activityProgress,
                    in: rect,
                    accent: accent,
                    opacity: elementOpacity,
                    textScale: element.textScale,
                    context: context
                )
            } else if element.kind == .route {
                if let sample {
                    drawRoute(
                        route,
                        current: sample.coordinate,
                        in: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08),
                        accent: accent,
                        lineWidth: configuration.preset == .runningFocus
                            ? max(2, rect.width * 0.020)
                            : nil,
                        context: context
                    )
                    if configuration.preset == .stadiumLive {
                        drawStadiumRouteTicks(in: rect, color: foreground, context: context)
                    }
                }
            } else if element.kind == .elevationProfile {
                drawElevationProfile(
                    elevationProfile,
                    current: sample,
                    in: rect,
                    accent: accent,
                    foreground: foreground,
                    textScale: element.textScale,
                    measurementUnit: element.effectiveMeasurementUnit ?? .meters,
                    language: videoTextLanguage,
                    context: context
                )
            } else if configuration.preset == .runningFocus {
                drawRunningFocusMetric(
                    kind: element.kind,
                    sample: sample,
                    clockTime: clockTime,
                    activityStart: activityStart,
                    language: videoTextLanguage,
                    textScale: element.textScale,
                    measurementUnit: element.effectiveMeasurementUnit,
                    clockDisplay: element.clockDisplay,
                    durationDisplay: element.durationDisplay,
                    in: rect,
                    color: foreground,
                    context: context
                )
            } else if configuration.preset == .stadiumLive {
                drawStadiumMetric(
                    kind: element.kind,
                    sample: sample,
                    clockTime: clockTime,
                    activityStart: activityStart,
                    language: videoTextLanguage,
                    textScale: element.textScale,
                    measurementUnit: element.effectiveMeasurementUnit,
                    clockDisplay: element.clockDisplay,
                    durationDisplay: element.durationDisplay,
                    in: rect,
                    color: foreground,
                    context: context
                )
            } else {
                drawMetric(
                    kind: element.kind,
                    sample: sample,
                    activityStart: activityStart,
                    clockTime: clockTime,
                    textScale: element.textScale,
                    measurementUnit: element.effectiveMeasurementUnit,
                    clockDisplay: element.clockDisplay,
                    durationDisplay: element.durationDisplay,
                    in: rect,
                    accent: accent,
                    foreground: foreground,
                    context: context
                )
            }
            context.restoreGState()
        }

        guard let image = context.makeImage() else {
            return nil
        }
        return CIImage(cgImage: image)
    }

    private func renderRect(_ frame: NormalizedRect, size: CGSize) -> CGRect {
        CGRect(
            x: frame.x * size.width,
            y: (1 - frame.y - frame.height) * size.height,
            width: frame.width * size.width,
            height: frame.height * size.height
        )
    }

    private func drawBackground(
        in rect: CGRect,
        preset: OverlayTemplatePreset,
        kind: OverlayElementKind,
        accent: CGColor,
        context: CGContext
    ) {
        if preset == .runningFocus {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.addPath(CGPath(
                roundedRect: rect,
                cornerWidth: rect.height * 0.12,
                cornerHeight: rect.height * 0.12,
                transform: nil
            ))
            context.fillPath()
            return
        }
        if preset == .stadiumLive {
            if kind != .route {
                context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                context.addPath(
                    CGPath(
                        roundedRect: rect,
                        cornerWidth: rect.height * 0.12,
                        cornerHeight: rect.height * 0.12,
                        transform: nil
                    )
                )
                context.fillPath()
                return
            }
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    CGColor(red: 0.65, green: 0.68, blue: 0.72, alpha: 1),
                    CGColor(red: 0.30, green: 0.34, blue: 0.38, alpha: 1)
                ] as CFArray,
                locations: [0, 1]
            ) else {
                return
            }
            context.saveGState()
            context.clip(to: rect)
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
            context.restoreGState()
            return
        }

        let radius: CGFloat
        switch preset {
        case .runningFocus: return
        case .minimal: radius = rect.height * 0.08
        case .sport, .track, .finishLine, .trail:
            radius = rect.height * 0.12
        case .technology: radius = rect.height * 0.03
        case .nightRun: radius = rect.height * 0.16
        case .stadiumLive: return
        }

        context.setFillColor(
            CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        )
        context.addPath(
            CGPath(
                roundedRect: rect,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
        )
        context.fillPath()

        if preset == .technology {
            context.setFillColor(accent)
            context.fill(
                CGRect(
                    x: rect.minX,
                    y: rect.maxY - max(2, rect.height * 0.025),
                    width: rect.width,
                    height: max(2, rect.height * 0.025)
                )
            )
        }
    }

    private func drawRunningFocusMetric(
        kind: OverlayElementKind,
        sample: ActivitySample?,
        clockTime: Date?,
        activityStart: Date?,
        language: VideoTextLanguage,
        textScale: Double,
        measurementUnit: OverlayMeasurementUnit?,
        clockDisplay: OverlayClockDisplay,
        durationDisplay: OverlayDurationDisplay,
        in rect: CGRect,
        color: CGColor,
        context: CGContext
    ) {
        if kind == .clockTime {
            let value = RunningFocusStyle.value(
                for: .clockTime,
                sample: sample,
                activityStart: activityStart,
                clockTime: clockTime,
                clockDisplay: clockDisplay
            )
            let fontSize = fittedFontSize(
                value,
                proposed: max(10, rect.height * 0.32 * textScale),
                width: max(1, rect.width - 8)
            )
            let valueWidth = textWidth(value, fontSize: fontSize, weight: .semibold)
            drawText(
                value,
                position: CGPoint(
                    x: rect.midX - valueWidth / 2,
                    y: rect.midY - fontSize * 0.34
                ),
                fontSize: fontSize,
                weight: .semibold,
                color: color,
                context: context
            )
            return
        }

        let value = RunningFocusStyle.value(
            for: kind,
            sample: sample,
            activityStart: activityStart,
            clockTime: clockTime,
            measurementUnit: measurementUnit,
            clockDisplay: clockDisplay,
            durationDisplay: durationDisplay
        )
        let label = RunningFocusStyle.label(
            for: kind,
            language: language,
            measurementUnit: measurementUnit
        )
        let availableWidth = max(1, rect.width - 8)
        let valueSize = fittedFontSize(
            value,
            proposed: max(12, rect.height * 0.52 * textScale),
            width: availableWidth
        )
        let labelSize = fittedFontSize(
            label,
            proposed: max(8, rect.height * 0.18 * textScale),
            width: availableWidth
        )
        let valueWidth = textWidth(value, fontSize: valueSize, weight: .semibold)
        let labelWidth = textWidth(label, fontSize: labelSize, weight: .medium)
        let gap = max(2, rect.height * 0.07)
        let contentHeight = valueSize + gap + labelSize
        let labelBaseline = rect.midY - contentHeight / 2 + labelSize * 0.20
        let valueBaseline = labelBaseline + labelSize + gap

        drawText(
            value,
            position: CGPoint(x: rect.midX - valueWidth / 2, y: valueBaseline),
            fontSize: valueSize,
            weight: .semibold,
            color: color,
            context: context
        )
        drawText(
            label,
            position: CGPoint(x: rect.midX - labelWidth / 2, y: labelBaseline),
            fontSize: labelSize,
            weight: .medium,
            color: color,
            context: context
        )
    }

    private func drawStadiumMetric(
        kind: OverlayElementKind,
        sample: ActivitySample?,
        clockTime: Date?,
        activityStart: Date?,
        language: VideoTextLanguage,
        textScale: Double,
        measurementUnit: OverlayMeasurementUnit?,
        clockDisplay: OverlayClockDisplay,
        durationDisplay: OverlayDurationDisplay,
        in rect: CGRect,
        color: CGColor,
        context: CGContext
    ) {
        let padding = max(2, min(12, rect.width * 0.035))
        let value = StadiumLiveStyle.value(
            for: kind,
            sample: sample,
            clockTime: clockTime,
            activityStart: activityStart,
            measurementUnit: measurementUnit,
            clockDisplay: clockDisplay,
            durationDisplay: durationDisplay
        )
        let rightAligned = kind == .altitude || kind == .distance || kind == .clockTime
        let availableWidth = max(1, rect.width - padding * 2)

        if kind == .heartRate {
            let diameter = min(rect.width * 0.26, rect.height * 0.47)
            let circle = CGRect(
                x: rect.minX + padding,
                y: rect.maxY - padding - diameter,
                width: diameter,
                height: diameter
            )
            context.setFillColor(
                CGColor(red: 0.84, green: 0.84, blue: 0.88, alpha: 0.50)
            )
            context.fillEllipse(in: circle)
            let iconSize = diameter * 0.74 * textScale
            let icon = "♥"
            let iconWidth = textWidth(icon, fontSize: iconSize, weight: .bold)
            drawText(
                icon,
                position: CGPoint(
                    x: circle.midX - iconWidth / 2,
                    y: circle.midY - iconSize * 0.34
                ),
                fontSize: iconSize,
                weight: .bold,
                color: color,
                context: context
            )
            let proposedSize = max(8, min(38, rect.height * 0.38) * textScale)
            let size = fittedFontSize(value, proposed: proposedSize, width: availableWidth)
            drawText(
                value,
                position: CGPoint(x: rect.minX + padding, y: rect.minY + padding),
                fontSize: size,
                weight: .semibold,
                color: color,
                context: context
            )
            return
        }

        let proposedValueSize = kind == .clockTime
            ? max(8, min(38, rect.height * 0.70) * textScale)
            : max(8, min(42, rect.height * 0.46) * textScale)
        let valueSize = fittedFontSize(
            value,
            proposed: proposedValueSize,
            width: availableWidth
        )
        let valueWidth = textWidth(value, fontSize: valueSize, weight: .semibold)
        drawText(
            value,
            position: CGPoint(
                x: rightAligned ? rect.maxX - padding - valueWidth : rect.minX + padding,
                y: rect.minY + max(2, rect.height * 0.09)
            ),
            fontSize: valueSize,
            weight: .semibold,
            color: color,
            context: context
        )
        guard kind != .clockTime else {
            return
        }

        let label = StadiumLiveStyle.label(for: kind, language: language)
        let proposedLabelSize = max(7, min(19, rect.height * 0.19) * textScale)
        let labelSize = fittedFontSize(
            label,
            proposed: proposedLabelSize,
            width: availableWidth
        )
        let labelWidth = textWidth(label, fontSize: labelSize, weight: .semibold)
        drawText(
            label,
            position: CGPoint(
                x: rightAligned ? rect.maxX - padding - labelWidth : rect.minX + padding,
                y: rect.maxY - padding - labelSize
            ),
            fontSize: labelSize,
            weight: .semibold,
            color: color,
            context: context
        )
    }

    private func fittedFontSize(
        _ text: String,
        proposed: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        proposed * min(
            1,
            width / max(textWidth(text, fontSize: proposed, weight: .semibold), 1)
        )
    }

    private func drawStadiumRouteTicks(
        in rect: CGRect,
        color: CGColor,
        context: CGContext
    ) {
        context.setStrokeColor(color)
        context.setLineWidth(max(1, rect.width * 0.009))
        let tick = min(rect.width, rect.height) * 0.10
        for x in [rect.minX, rect.maxX] {
            context.move(to: CGPoint(x: x, y: rect.midY - tick / 2))
            context.addLine(to: CGPoint(x: x, y: rect.midY + tick / 2))
        }
        context.strokePath()
    }

    private func drawMetric(
        kind: OverlayElementKind,
        sample: ActivitySample?,
        activityStart: Date?,
        clockTime: Date?,
        textScale: Double,
        measurementUnit: OverlayMeasurementUnit?,
        clockDisplay: OverlayClockDisplay,
        durationDisplay: OverlayDurationDisplay,
        in rect: CGRect,
        accent: CGColor,
        foreground: CGColor,
        context: CGContext
    ) {
        let padding = max(6, rect.width * 0.06)
        if kind == .clockTime {
            drawClockTime(
                clockTime,
                textScale: textScale,
                clockDisplay: clockDisplay,
                in: rect,
                padding: padding,
                foreground: foreground,
                context: context
            )
            return
        }

        let valueSize = max(9, rect.height * 0.36 * textScale)
        let value = metricValue(
            kind: kind,
            sample: sample,
            activityStart: activityStart,
            clockTime: clockTime,
            measurementUnit: measurementUnit,
            clockDisplay: clockDisplay,
            durationDisplay: durationDisplay
        )
        let unit = metricUnit(kind, measurementUnit: measurementUnit)
        let availableWidth = max(1, rect.width - padding * 2)
        let proposedUnitSize = max(9, valueSize * 0.35)
        let proposedValueWidth = textWidth(
            value,
            fontSize: valueSize,
            weight: .bold
        )
        let proposedUnitWidth = unit.isEmpty ? 0 : textWidth(
            unit,
            fontSize: proposedUnitSize,
            weight: .bold
        ) + 4
        let textScale = min(
            1,
            availableWidth / max(proposedValueWidth + proposedUnitWidth, 1)
        )
        let valueFontSize = valueSize * textScale
        let unitFontSize = proposedUnitSize * textScale
        let baseline = rect.midY - valueFontSize * 0.35
        drawText(
            value,
            position: CGPoint(
                x: rect.minX + padding,
                y: baseline
            ),
            fontSize: valueFontSize,
            weight: .bold,
            color: foreground,
            context: context
        )

        let valueWidth = textWidth(
            value,
            fontSize: valueFontSize,
            weight: .bold
        )
        drawText(
            unit,
            position: CGPoint(
                x: rect.minX + padding + valueWidth + 4 * textScale,
                y: baseline + valueFontSize * 0.06
            ),
            fontSize: unitFontSize,
            weight: .bold,
            color: accent,
            context: context
        )
    }

    private func drawClockTime(
        _ clockTime: Date?,
        textScale: Double,
        clockDisplay: OverlayClockDisplay,
        in rect: CGRect,
        padding: CGFloat,
        foreground: CGColor,
        context: CGContext
    ) {
        let value = RunOverlayFormatters.clock(clockTime, display: clockDisplay)
        let availableWidth = max(1, rect.width - padding * 2)
        let proposedSize = max(9, rect.height * 0.34 * textScale)
        let fontSize = min(
            proposedSize,
            proposedSize * availableWidth /
                max(textWidth(value, fontSize: proposedSize, weight: .bold), 1)
        )
        drawText(
            value,
            position: CGPoint(
                x: rect.minX + padding,
                y: rect.midY - fontSize * 0.35
            ),
            fontSize: fontSize,
            weight: .bold,
            color: foreground,
            context: context
        )
    }

    private func drawRoute(
        _ coordinates: [GeoCoordinate],
        current: GeoCoordinate?,
        in rect: CGRect,
        accent: CGColor,
        lineWidth: CGFloat? = nil,
        context: CGContext
    ) {
        let displayCoordinates = downsampled(coordinates, maximumCount: 1_000)
        let points = project(displayCoordinates, in: rect)
        guard let first = points.first else {
            return
        }

        context.setStrokeColor(accent)
        context.setLineWidth(lineWidth ?? max(2, rect.width * 0.012))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()

        if let current,
           let point = project([current], in: rect, bounds: displayCoordinates).first {
            let radius = max(4, rect.width * 0.025)
            context.setFillColor(
                CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            )
            context.fillEllipse(
                in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        }
    }

    private func drawElevationProfile(
        _ profile: ElevationProfile?,
        current: ActivitySample?,
        in rect: CGRect,
        accent: CGColor,
        foreground: CGColor,
        textScale: Double,
        measurementUnit: OverlayMeasurementUnit,
        language: VideoTextLanguage,
        context: CGContext
    ) {
        guard rect.width > 10, rect.height > 10 else { return }
        let plot = ElevationProfile.plotRect(in: rect, originAtTop: false)
        let label = RunOverlayLocalization.text("profile.ascent", videoLanguage: language)
        let amount = OverlayMeasurementFormatter.elevation(
            meters: current?.ascentMeters,
            unit: measurementUnit
        ) ?? "—"
        let value = "\(amount) \(measurementUnit.symbol)"
        let labelSize = fittedFontSize(
            label,
            proposed: max(7, rect.height * 0.11 * textScale),
            width: max(1, rect.width * 0.43)
        )
        let valueSize = fittedFontSize(
            value,
            proposed: max(9, rect.height * 0.20 * textScale),
            width: max(1, rect.width * 0.48)
        )
        drawText(
            label,
            position: CGPoint(x: plot.minX, y: rect.maxY - labelSize * 1.30),
            fontSize: labelSize,
            weight: .medium,
            color: foreground,
            context: context
        )
        let valueWidth = textWidth(value, fontSize: valueSize, weight: .semibold)
        drawText(
            value,
            position: CGPoint(x: plot.maxX - valueWidth, y: rect.maxY - valueSize * 1.18),
            fontSize: valueSize,
            weight: .semibold,
            color: foreground,
            context: context
        )
        let distanceLabels = profile?.distanceLabels ?? (start: "0 km", end: "— km")
        let distanceSize = max(6, rect.height * 0.10 * textScale)
        drawText(
            distanceLabels.start,
            position: CGPoint(x: plot.minX, y: rect.minY + rect.height * 0.045),
            fontSize: distanceSize,
            weight: .medium,
            color: foreground,
            context: context
        )
        let endWidth = textWidth(
            distanceLabels.end,
            fontSize: distanceSize,
            weight: .medium
        )
        drawText(
            distanceLabels.end,
            position: CGPoint(
                x: plot.maxX - endWidth,
                y: rect.minY + rect.height * 0.045
            ),
            fontSize: distanceSize,
            weight: .medium,
            color: foreground,
            context: context
        )
        guard let profile, profile.isAvailable else { return }
        context.saveGState()
        context.setStrokeColor(foreground.copy(alpha: 0.25) ?? foreground)
        context.setLineWidth(max(1, rect.height * 0.009))
        context.move(to: CGPoint(x: plot.minX, y: plot.minY))
        context.addLine(to: CGPoint(x: plot.maxX, y: plot.minY))
        context.strokePath()

        let marker = profile.marker(for: current, in: plot, originAtTop: false)
        let line = CGMutablePath()
        for point in profile.points {
            let projected = profile.position(for: point, in: plot, originAtTop: false)
            if point.startsNewSegment || line.isEmpty {
                line.move(to: projected)
            } else {
                line.addLine(to: projected)
            }
        }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(max(1.5, rect.height * 0.017))
        context.setStrokeColor(foreground.copy(alpha: 0.42) ?? foreground)
        context.addPath(line)
        context.strokePath()
        if let marker {
            context.saveGState()
            context.clip(to: CGRect(
                x: plot.minX, y: plot.minY,
                width: max(0, marker.x - plot.minX),
                height: plot.height
            ))
            context.setStrokeColor(accent)
            context.addPath(line)
            context.strokePath()
            context.restoreGState()
            let radius = max(3, min(5, rect.height * 0.033))
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fillEllipse(in: CGRect(
                x: marker.x - radius, y: marker.y - radius,
                width: radius * 2, height: radius * 2
            ))
        }
        context.restoreGState()
    }

    private func drawProgress(
        _ progress: ActivityProgress?,
        in rect: CGRect,
        accent: CGColor,
        opacity: Double,
        textScale: Double,
        context: CGContext
    ) {
        let layout = RunningProgressBarLayout(
            in: rect,
            progress: progress?.fraction,
            originAtTop: false
        )
        guard layout.track.width > 0 else { return }
        let trackPath = CGPath(
            roundedRect: layout.track,
            cornerWidth: layout.track.height / 2,
            cornerHeight: layout.track.height / 2,
            transform: nil
        )

        context.saveGState()
        context.setAlpha(CGFloat(opacity * 0.30))
        context.setFillColor(accent)
        context.addPath(trackPath)
        context.fillPath()
        context.restoreGState()

        if layout.fill.width > 0 {
            context.saveGState()
            context.addPath(trackPath)
            context.clip()
            context.setFillColor(accent)
            context.fill(layout.fill)
            context.restoreGState()
        }

        let labels = [
            progress?.startLabel ?? "0km",
            progress?.totalLabel ?? "— km"
        ]
        let slotWidth = max(1, layout.labels.width / 2)
        let proposedSize = max(
            6,
            layout.labels.height * RunningProgressBarLayout.labelHeightFraction * textScale
        )
        let fontSize = labels.reduce(proposedSize) { size, text in
            min(
                size,
                fittedFontSize(text, proposed: proposedSize, width: slotWidth)
            )
        }
        for (index, text) in labels.enumerated() {
            let width = textWidth(text, fontSize: fontSize, weight: .semibold)
            let x = index == 0 ? layout.labels.minX : layout.labels.maxX - width
            drawText(
                text,
                position: CGPoint(
                    x: x,
                    y: layout.labels.midY - fontSize * 0.34
                ),
                fontSize: fontSize,
                weight: .semibold,
                color: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                context: context
            )
        }
        let currentText = progress?.currentLabel ?? "— km"
        let currentSize = fittedFontSize(
            currentText,
            proposed: max(
                6,
                layout.currentLabel.height *
                    RunningProgressBarLayout.labelHeightFraction * textScale
            ),
            width: max(1, layout.currentLabel.width - 2)
        )
        let currentWidth = textWidth(
            currentText,
            fontSize: currentSize,
            weight: .semibold
        )
        drawText(
            currentText,
            position: CGPoint(
                x: layout.currentLabelCenterX(forTextWidth: currentWidth) -
                    currentWidth / 2,
                y: layout.currentLabel.midY - currentSize * 0.34
            ),
            fontSize: currentSize,
            weight: .semibold,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            context: context
        )
    }

    private func drawText(
        _ text: String,
        position: CGPoint,
        fontSize: CGFloat,
        weight: FontWeight,
        color: CGColor,
        context: CGContext
    ) {
        let font = CTFontCreateWithName(
            weight.postScriptName as CFString,
            fontSize,
            nil
        )
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
        context.textPosition = position
        CTLineDraw(line, context)
    }

    private func textWidth(
        _ text: String,
        fontSize: CGFloat,
        weight: FontWeight
    ) -> CGFloat {
        let font = CTFontCreateWithName(
            weight.postScriptName as CFString,
            fontSize,
            nil
        )
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font
                ]
            )
        )
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func metricValue(
        kind: OverlayElementKind,
        sample: ActivitySample?,
        activityStart: Date?,
        clockTime: Date?,
        measurementUnit: OverlayMeasurementUnit?,
        clockDisplay: OverlayClockDisplay,
        durationDisplay: OverlayDurationDisplay
    ) -> String {
        switch kind {
        case .pace:
            guard let pace = OverlayMeasurementFormatter.pace(
                speedMetersPerSecond: sample?.speedMetersPerSecond,
                unit: measurementUnit ?? .kilometers
            ) else {
                return "—:—"
            }
            return String(format: "%d:%02d", pace.minutes, pace.seconds)
        case .distance:
            return OverlayMeasurementFormatter.distance(
                meters: sample?.distanceMeters,
                unit: measurementUnit ?? .kilometers
            ) ?? "—"
        case .elapsedTime:
            return RunOverlayFormatters.activityDuration(
                sample: sample,
                start: activityStart,
                display: durationDisplay
            )
        case .clockTime:
            return RunOverlayFormatters.clock(clockTime, display: clockDisplay)
        case .heartRate:
            return integerText(sample?.heartRate)
        case .cadence:
            return integerText(sample?.cadence)
        case .power:
            return integerText(sample?.power)
        case .altitude:
            return OverlayMeasurementFormatter.elevation(
                meters: sample?.altitudeMeters,
                unit: measurementUnit ?? .meters
            ) ?? "—"
        case .ascent:
            return OverlayMeasurementFormatter.elevation(
                meters: sample?.ascentMeters,
                unit: measurementUnit ?? .meters
            ) ?? "—"
        case .calories:
            return integerText(sample?.caloriesKilocalories)
        case .route, .progress, .elevationProfile:
            return ""
        }
    }

    private func metricUnit(
        _ kind: OverlayElementKind,
        measurementUnit: OverlayMeasurementUnit?
    ) -> String {
        switch kind {
        case .pace: measurementUnit == .miles ? "/MI" : "/KM"
        case .distance: measurementUnit == .miles ? "MI" : "KM"
        case .elapsedTime, .clockTime: ""
        case .heartRate: "BPM"
        case .cadence: "SPM"
        case .power: "W"
        case .altitude, .ascent: measurementUnit == .feet ? "FT" : "M"
        case .calories: "KCAL"
        case .route, .progress, .elevationProfile: ""
        }
    }

    private func integerText(_ value: Double?) -> String {
        value.map { String(Int($0.rounded())) } ?? "—"
    }

    private func color(from hex: String) -> CGColor {
        let text = hex.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
        let value = UInt64(text, radix: 16) ?? 0xFFFFFF
        return CGColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private func downsampled(
        _ coordinates: [GeoCoordinate],
        maximumCount: Int
    ) -> [GeoCoordinate] {
        guard coordinates.count > maximumCount else {
            return coordinates
        }
        let step = max(1, coordinates.count / maximumCount)
        var result = Swift.stride(from: 0, to: coordinates.count, by: step)
            .map { coordinates[$0] }
        if let last = coordinates.last, result.last != last {
            result.append(last)
        }
        return result
    }

    private func project(
        _ coordinates: [GeoCoordinate],
        in rect: CGRect,
        bounds: [GeoCoordinate]? = nil
    ) -> [CGPoint] {
        RouteProjection.coreGraphicsPoints(
            for: coordinates,
            in: rect,
            using: bounds
        )
    }
}
