import RunOverlayCore
import SwiftUI

struct RouteCalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedSample: ActivitySample?

    private var routeSamples: [ActivitySample] {
        appModel.project.activitySamples.filter { $0.coordinate != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(AppStrings.text("ui.route.title"))
                    .font(.title2.bold())
                Text(AppStrings.text("ui.route.instruction"))
                    .foregroundStyle(.secondary)
            }

            RouteCalibrationCanvas(
                samples: routeSamples,
                selectedSample: $selectedSample
            )
            .frame(minWidth: 560, minHeight: 360)
            .background(EditorTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                if let selectedSample,
                   let start = appModel.project.activitySource?.timeRange?.start {
                    Text(
                        AppStrings.format(
                            "ui.route.selectedAfter",
                            RunOverlayFormatters.duration(
                                selectedSample.timestamp.timeIntervalSince(start)
                            )
                        )
                    )
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                } else {
                    Text(AppStrings.text("ui.route.clickInstruction"))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(AppStrings.text("ui.common.cancel")) {
                    dismiss()
                }
                .buttonStyle(EditorActionButtonStyle(tone: .outline))

                Button(AppStrings.text("ui.route.apply")) {
                    if let selectedSample {
                        appModel.calibrateSelectedVideo(to: selectedSample)
                    }
                    dismiss()
                }
                .buttonStyle(EditorActionButtonStyle(tone: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(selectedSample == nil)
            }
        }
        .padding(24)
        .background(EditorTheme.sidebar)
    }
}

private struct RouteCalibrationCanvas: View {
    let samples: [ActivitySample]
    @Binding var selectedSample: ActivitySample?

    var body: some View {
        GeometryReader { proxy in
            let projection = RouteProjection(
                coordinates: samples.compactMap(\.coordinate),
                size: proxy.size
            )

            ZStack {
                Canvas { context, _ in
                    var path = Path()
                    guard let first = projection.points.first else {
                        return
                    }
                    path.move(to: first)
                    for point in projection.points.dropFirst() {
                        path.addLine(to: point)
                    }
                    context.stroke(
                        path,
                        with: .color(.accentColor.opacity(0.82)),
                        style: StrokeStyle(
                            lineWidth: 4,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                    if let coordinate = selectedSample?.coordinate {
                        let point = projection.point(for: coordinate)
                        let marker = CGRect(
                            x: point.x - 7,
                            y: point.y - 7,
                            width: 14,
                            height: 14
                        )
                        context.fill(
                            Path(ellipseIn: marker),
                            with: .color(.white)
                        )
                        context.stroke(
                            Path(ellipseIn: marker),
                            with: .color(.accentColor),
                            lineWidth: 3
                        )
                    }
                }

                if samples.isEmpty {
                    ContentUnavailableView(
                        AppStrings.text("ui.route.emptyTitle"),
                        systemImage: "location.slash"
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        selectedSample = nearestSample(
                            to: value.location,
                            points: projection.points
                        )
                    }
            )
        }
        .padding(24)
    }

    private func nearestSample(
        to location: CGPoint,
        points: [CGPoint]
    ) -> ActivitySample? {
        guard points.count == samples.count else {
            return nil
        }
        let match = points.enumerated().min { first, second in
            squaredDistance(first.element, location) <
                squaredDistance(second.element, location)
        }
        return match.map { samples[$0.offset] }
    }

    private func squaredDistance(_ first: CGPoint, _ second: CGPoint) -> Double {
        let x = first.x - second.x
        let y = first.y - second.y
        return x * x + y * y
    }
}

private struct RouteProjection {
    let coordinates: [GeoCoordinate]
    let size: CGSize
    let points: [CGPoint]
    private let averageLatitude: Double
    private let minimumX: Double
    private let minimumY: Double
    private let rangeX: Double
    private let rangeY: Double
    private let padding = 14.0

    init(coordinates: [GeoCoordinate], size: CGSize) {
        self.coordinates = coordinates
        self.size = size
        let computedAverageLatitude = coordinates.isEmpty
            ? 0
            : coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)

        let scale = cos(computedAverageLatitude * .pi / 180)
        let projected = coordinates.map {
            (x: $0.longitude * scale, y: $0.latitude)
        }
        let computedMinimumX = projected.map(\.x).min() ?? 0
        let computedMinimumY = projected.map(\.y).min() ?? 0
        let maximumX = projected.map(\.x).max() ?? 1
        let maximumY = projected.map(\.y).max() ?? 1
        let computedRangeX = max(maximumX - computedMinimumX, 0.000_001)
        let computedRangeY = max(maximumY - computedMinimumY, 0.000_001)
        let contentPadding = 14.0

        points = coordinates.map {
            let x = ($0.longitude * scale - computedMinimumX) / computedRangeX
            let y = ($0.latitude - computedMinimumY) / computedRangeY
            return CGPoint(
                x: contentPadding + x * max(0, size.width - contentPadding * 2),
                y: contentPadding + (1 - y) * max(0, size.height - contentPadding * 2)
            )
        }
        averageLatitude = computedAverageLatitude
        minimumX = computedMinimumX
        minimumY = computedMinimumY
        rangeX = computedRangeX
        rangeY = computedRangeY
    }

    func point(for coordinate: GeoCoordinate) -> CGPoint {
        let scale = cos(averageLatitude * .pi / 180)
        let x = (coordinate.longitude * scale - minimumX) / rangeX
        let y = (coordinate.latitude - minimumY) / rangeY
        return CGPoint(
            x: padding + x * max(0, size.width - padding * 2),
            y: padding + (1 - y) * max(0, size.height - padding * 2)
        )
    }
}
