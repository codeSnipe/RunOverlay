import Foundation

public struct EditHistory<State: Equatable>: Equatable {
    public struct Step: Equatable {
        public let action: String
        public let state: State

        public init(action: String, state: State) {
            self.action = action
            self.state = state
        }
    }

    public let limit: Int
    public private(set) var undoSteps: [Step] = []
    public private(set) var redoSteps: [Step] = []

    public init(limit: Int = 50) {
        self.limit = max(1, limit)
    }

    public var canUndo: Bool { !undoSteps.isEmpty }
    public var canRedo: Bool { !redoSteps.isEmpty }

    public mutating func record(action: String, before: State, after: State) {
        guard before != after else { return }
        undoSteps.append(Step(action: action, state: before))
        if undoSteps.count > limit {
            undoSteps.removeFirst(undoSteps.count - limit)
        }
        redoSteps.removeAll()
    }

    public mutating func replaceLatestUndo(
        action: String,
        before: State,
        after: State
    ) {
        guard before != after else { return }
        if !undoSteps.isEmpty {
            undoSteps.removeLast()
        }
        record(action: action, before: before, after: after)
    }

    public mutating func undo(current: State) -> State? {
        guard let previous = undoSteps.popLast() else { return nil }
        redoSteps.append(Step(action: previous.action, state: current))
        return previous.state
    }

    public mutating func redo(current: State) -> State? {
        guard let next = redoSteps.popLast() else { return nil }
        undoSteps.append(Step(action: next.action, state: current))
        return next.state
    }

    public mutating func clear() {
        undoSteps.removeAll()
        redoSteps.removeAll()
    }
}
