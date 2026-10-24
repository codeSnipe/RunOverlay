import AppKit
import CoreGraphics
import Foundation

struct AppIconGenerator {
    private static let canvasSize: CGFloat = 1_024
    private static let background = CGColor(
        srgbRed: 0.075,
        green: 0.106,
        blue: 0.090,
        alpha: 1
    )
    private static let panel = CGColor(
        srgbRed: 0.105,
        green: 0.149,
        blue: 0.122,
        alpha: 1
    )
    private static let line = CGColor(
        srgbRed: 0.91,
        green: 0.96,
        blue: 0.91,
        alpha: 0.76
    )
    private static let accent = CGColor(
        srgbRed: 0.82,
        green: 0.97,
        blue: 0.34,
        alpha: 1
    )

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(
                domain: "AppIconGenerator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "请提供 AppIcon.appiconset 输出目录。"]
            )
        }

        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let master = try render(size: 1_024)

        let sizes: [(name: String, pixels: Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1_024)
        ]

        for item in sizes {
            let image = item.pixels == 1_024
                ? master
                : try render(size: item.pixels)
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(
                    domain: "AppIconGenerator",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "无法编码图标 PNG。"]
                )
            }
            try data.write(to: outputDirectory.appendingPathComponent(item.name))
        }
    }

    private static func render(size: Int) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(
                domain: "AppIconGenerator",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "无法创建图标绘图上下文。"]
            )
        }

        let scale = CGFloat(size) / canvasSize
        context.scaleBy(x: scale, y: scale)
        drawBackground(in: context)
        drawViewfinder(in: context)
        drawTelemetry(in: context)
        drawRoute(in: context)

        guard let image = context.makeImage() else {
            throw NSError(
                domain: "AppIconGenerator",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "无法生成图标图像。"]
            )
        }
        return image
    }

    private static func drawBackground(in context: CGContext) {
        let bounds = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        context.setFillColor(background)
        context.addPath(
            CGPath(
                roundedRect: bounds,
                cornerWidth: 224,
                cornerHeight: 224,
                transform: nil
            )
        )
        context.fillPath()

        let inset = bounds.insetBy(dx: 18, dy: 18)
        context.setFillColor(panel)
        context.addPath(
            CGPath(
                roundedRect: inset,
                cornerWidth: 210,
                cornerHeight: 210,
                transform: nil
            )
        )
        context.fillPath()

        context.setStrokeColor(
            CGColor(srgbRed: 0.91, green: 0.96, blue: 0.91, alpha: 0.1)
        )
        context.setLineWidth(3)
        context.addPath(
            CGPath(
                roundedRect: inset.insetBy(dx: 2, dy: 2),
                cornerWidth: 208,
                cornerHeight: 208,
                transform: nil
            )
        )
        context.strokePath()
    }

    private static func drawViewfinder(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(line)
        context.setLineWidth(20)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let corners: [[CGPoint]] = [
            [CGPoint(x: 246, y: 402), CGPoint(x: 246, y: 650), CGPoint(x: 350, y: 650)],
            [CGPoint(x: 674, y: 650), CGPoint(x: 778, y: 650), CGPoint(x: 778, y: 546)],
            [CGPoint(x: 246, y: 710), CGPoint(x: 246, y: 762), CGPoint(x: 298, y: 762)],
            [CGPoint(x: 726, y: 762), CGPoint(x: 778, y: 762), CGPoint(x: 778, y: 710)]
        ]
        for points in corners {
            context.beginPath()
            context.move(to: points[0])
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func drawTelemetry(in context: CGContext) {
        context.saveGState()
        context.setFillColor(line)
        let bars: [CGFloat] = [82, 58, 72]
        for (index, width) in bars.enumerated() {
            let rect = CGRect(
                x: 642,
                y: 772 - CGFloat(index) * 34,
                width: width,
                height: 12
            )
            context.addPath(
                CGPath(
                    roundedRect: rect,
                    cornerWidth: 6,
                    cornerHeight: 6,
                    transform: nil
                )
            )
            context.fillPath()
        }
        context.restoreGState()
    }

    private static func drawRoute(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(accent)
        context.setLineWidth(30)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: CGPoint(x: 314, y: 332))
        context.addCurve(
            to: CGPoint(x: 486, y: 472),
            control1: CGPoint(x: 370, y: 294),
            control2: CGPoint(x: 408, y: 500)
        )
        context.addCurve(
            to: CGPoint(x: 674, y: 474),
            control1: CGPoint(x: 578, y: 454),
            control2: CGPoint(x: 620, y: 402)
        )
        context.addCurve(
            to: CGPoint(x: 724, y: 662),
            control1: CGPoint(x: 766, y: 566),
            control2: CGPoint(x: 634, y: 598)
        )
        context.strokePath()

        let start = CGPoint(x: 314, y: 332)
        context.setFillColor(panel)
        context.fillEllipse(
            in: CGRect(x: start.x - 17, y: start.y - 17, width: 34, height: 34)
        )
        context.setStrokeColor(accent)
        context.setLineWidth(8)
        context.strokeEllipse(
            in: CGRect(x: start.x - 24, y: start.y - 24, width: 48, height: 48)
        )

        let finish = CGPoint(x: 724, y: 662)
        context.setFillColor(accent)
        context.fillEllipse(
            in: CGRect(x: finish.x - 37, y: finish.y - 37, width: 74, height: 74)
        )
        context.setFillColor(panel)
        context.fillEllipse(
            in: CGRect(x: finish.x - 15, y: finish.y - 15, width: 30, height: 30)
        )
        context.restoreGState()
    }
}

try AppIconGenerator.main()
