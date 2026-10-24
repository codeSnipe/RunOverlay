import XCTest
@testable import RunOverlayCore

final class EditHistoryTests: XCTestCase {
    func test多步撤销重做并可清除将来分支() {
        var history = EditHistory<Int>()
        history.record(action: "导入视频", before: 0, after: 1)
        history.record(action: "调整图层", before: 1, after: 2)
        XCTAssertEqual(history.undo(current: 2), 1)
        XCTAssertEqual(history.undo(current: 1), 0)
        XCTAssertEqual(history.redo(current: 0), 1)
        XCTAssertEqual(history.undoSteps.map(\.action), ["导入视频"])
        XCTAssertEqual(history.redoSteps.map(\.action), ["调整图层"])

        history.record(action: "选择模板", before: 1, after: 3)
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.undo(current: 3), 1)
        XCTAssertEqual(history.redo(current: 1), 3)
    }

    func test无变化不生成操作且只保留最近步骤() {
        var history = EditHistory<Int>(limit: 2)
        history.record(action: "未改变", before: 0, after: 0)
        XCTAssertFalse(history.canUndo)
        history.record(action: "第一步", before: 0, after: 1)
        history.record(action: "第二步", before: 1, after: 2)
        history.record(action: "第三步", before: 2, after: 3)

        XCTAssertEqual(history.undoSteps.map(\.action), ["第二步", "第三步"])
        XCTAssertEqual(history.undo(current: 3), 2)
        XCTAssertEqual(history.undo(current: 2), 1)
        XCTAssertNil(history.undo(current: 1))
        history.clear()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func test连续调整合并后仍可撤销到开始状态() {
        var history = EditHistory<Int>()
        history.record(action: "时间偏移", before: 0, after: 1)
        history.replaceLatestUndo(action: "时间偏移", before: 0, after: 2)
        history.replaceLatestUndo(action: "时间偏移", before: 0, after: 3)

        XCTAssertEqual(history.undoSteps.count, 1)
        XCTAssertEqual(history.undo(current: 3), 0)
        XCTAssertEqual(history.redo(current: 0), 3)
    }
}
