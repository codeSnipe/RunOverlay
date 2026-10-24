import Foundation
import XCTest
@testable import RunOverlayCore

final class DiskSpaceEstimatorTests: XCTestCase {
    func test估算量包含编码余量和安全缓冲() throws {
        let directory = FileManager.default.temporaryDirectory
        let estimator = DiskSpaceEstimator()
        let h264 = try estimator.estimate(
            inputBytes: [1_000_000, 2_000_000],
            outputDirectory: directory,
            outputCodec: .h264
        )
        let hevc = try estimator.estimate(
            inputBytes: [1_000_000, 2_000_000],
            outputDirectory: directory,
            outputCodec: .hevc
        )

        XCTAssertGreaterThan(h264.requiredBytes, 3_000_000)
        XCTAssertGreaterThan(hevc.requiredBytes, 3_000_000)
        XCTAssertLessThan(hevc.requiredBytes, h264.requiredBytes)
        XCTAssertGreaterThan(h264.availableBytes, 0)
    }
}
