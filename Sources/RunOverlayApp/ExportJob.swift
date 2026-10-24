import Foundation
import RunOverlayCore

enum ExportJobStatus: Equatable {
    case waiting
    case exporting
    case completed
    case failed(String)
    case cancelled

    var displayName: String {
        switch self {
        case .waiting: AppStrings.text("export.status.waiting")
        case .exporting: AppStrings.text("export.status.exporting")
        case .completed: AppStrings.text("export.status.completed")
        case .failed: AppStrings.text("export.status.failed")
        case .cancelled: AppStrings.text("export.status.cancelled")
        }
    }

    var systemImage: String {
        switch self {
        case .waiting: "clock"
        case .exporting: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }
}

struct ExportJob: Identifiable {
    let id: UUID
    let videoID: UUID
    let fileName: String
    /// 点击开始时固定每段视频的输入、数据与蒙层配置，后台编辑不影响待执行任务。
    let request: VideoExportRequest
    var outputURL: URL
    var status: ExportJobStatus
    var progress: Double
}
