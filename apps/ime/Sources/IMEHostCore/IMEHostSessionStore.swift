import Foundation
import SharedModels

public final class IMEHostSessionStore {
    public private(set) var state: CompositionState

    public init(initialState: CompositionState = CompositionState()) {
        self.state = initialState
    }

    public func apply(_ update: InputSessionUpdate) {
        state = update.state
    }

    public func reset() {
        state = CompositionState(mode: state.mode, recentText: state.recentText)
    }
}
