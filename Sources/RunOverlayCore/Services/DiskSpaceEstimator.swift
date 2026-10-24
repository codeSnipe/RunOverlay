import Foundation

public struct DiskSpaceEstimate: Hashable, Sendable {
    public var requiredBytes: Int64
    public var availableBytes: Int64

    public var hasEnoughSpace: Bool {
        availableBytes >= requiredBytes
    }

    public init(requiredBytes: Int64, availableBytes: Int64) {
        self.requiredBytes = requiredBytes
        self.availableBytes = availableBytes
    }
}

public struct DiskSpaceEstimator: Sendable {
    public init() {}

    public func estimate(
        inputBytes: [Int64],
        outputDirectory: URL,
        outputCodec: ExportSettings.Codec
    ) throws -> DiskSpaceEstimate {
        let attributes = try FileManager.default.attributesOfFileSystem(
            forPath: outputDirectory.path
        )
        let available = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let validSizes = inputBytes.filter { $0 > 0 }
        let totalInputBytes = validSizes.reduce(Int64.zero, +)

        // 有损编码大小受画面复杂度影响，按输入体积 1.5 倍预留，并加固定余量。
        let multiplier: Double = outputCodec == .hevc ? 1.2 : 1.5
        let estimatedOutput = Int64((Double(totalInputBytes) * multiplier).rounded(.up))
        let safetyBuffer = max(Int64(512 * 1_024 * 1_024), totalInputBytes / 10)

        return DiskSpaceEstimate(
            requiredBytes: estimatedOutput + safetyBuffer,
            availableBytes: available
        )
    }
}
