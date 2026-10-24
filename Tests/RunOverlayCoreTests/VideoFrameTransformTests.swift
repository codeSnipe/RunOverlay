import CoreImage
import XCTest
@testable import RunOverlayCore

final class VideoFrameTransformTests: XCTestCase {
    func test旋转方向与输出尺寸() throws {
        let red = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        let blue = CIImage(color: .blue).cropped(to: CGRect(x: 2, y: 0, width: 2, height: 2))
        let source = red.composited(over: blue)
        let context = CIContext(options: [.useSoftwareRenderer: true])

        func pixel(_ image: CIImage, x: Int, y: Int) throws -> [UInt8] {
            var result = [UInt8](repeating: 0, count: 4)
            context.render(
                image,
                toBitmap: &result,
                rowBytes: 4,
                bounds: CGRect(x: x, y: y, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
            return result
        }

        let clockwise = VideoFrameTransform.rotated(source, by: .clockwise90)
        XCTAssertEqual(clockwise.extent, CGRect(x: 0, y: 0, width: 2, height: 4))
        let top = try pixel(clockwise, x: 0, y: 3)
        let bottom = try pixel(clockwise, x: 0, y: 0)
        XCTAssertGreaterThan(top[0], top[2], "顺时针旋转后原画面左侧应在上方")
        XCTAssertGreaterThan(bottom[2], bottom[0])

        let counterclockwise = VideoFrameTransform.rotated(
            source, by: .counterclockwise90
        )
        XCTAssertEqual(counterclockwise.extent, clockwise.extent)
        let otherTop = try pixel(counterclockwise, x: 0, y: 3)
        XCTAssertGreaterThan(otherTop[2], otherTop[0])

        let halfTurn = VideoFrameTransform.rotated(source, by: .halfTurn)
        XCTAssertEqual(halfTurn.extent, source.extent)
        let right = try pixel(halfTurn, x: 3, y: 0)
        XCTAssertGreaterThan(right[0], right[2])
        XCTAssertEqual(VideoFrameTransform.rotated(source, by: .none).extent, source.extent)
    }
}
