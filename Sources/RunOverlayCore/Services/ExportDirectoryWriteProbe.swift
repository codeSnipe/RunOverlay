import Foundation

/// 在当前进程的沙盒权限下实际创建并移除临时文件，避免只检查目录存在就启动导出。
public struct ExportDirectoryWriteProbe: Sendable {
    public init() {}

    public func verify(_ directory: URL) throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw CocoaError(.fileWriteNoPermission)
        }

        let probe = directory.appendingPathComponent(
            ".runoverlay-write-check-\(UUID().uuidString)"
        )
        do {
            try Data([0x52]).write(to: probe, options: .withoutOverwriting)
        } catch {
            // 写入若中途失败，只清理本次生成的唯一临时文件。
            try? FileManager.default.removeItem(at: probe)
            throw error
        }
        try FileManager.default.removeItem(at: probe)
    }
}
