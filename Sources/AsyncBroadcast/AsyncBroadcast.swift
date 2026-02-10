import Foundation

/// A lightweight 1-to-N broadcast channel for Swift Concurrency.
///
/// Each call to `makeStream()` creates a new subscriber that receives every
/// value sent after subscription. The channel is thread-safe..
public final class AsyncBroadcast<Element: Sendable>: Sendable {
    private struct StateData: Sendable {
        var continuations: [UUID: AsyncStream<Element>.Continuation]
        var isFinished: Bool

        init() {
            self.continuations = [:]
            self.isFinished = false
        }
    }

    private let storage: Locked<StateData>
    private let defaultBufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy

    public init(
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded
    ) {
        self.storage = Locked(value: StateData())
        self.defaultBufferingPolicy = bufferingPolicy
    }

    /// Creates a new subscriber stream.
    public func makeStream(
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy? = nil
    ) -> AsyncStream<Element> {
        let policy = bufferingPolicy ?? defaultBufferingPolicy
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: policy)
        if Task.isCancelled {
            continuation.finish()
            return stream
        }
        let shouldFinish = storage.write { state in
            if state.isFinished {
                return true
            }
            state.continuations[id] = continuation
            return false
        }
        if shouldFinish {
            continuation.finish()
            return stream
        }
        continuation.onTermination = { [weak self] a in
            self?.storage.write { state in
                state.continuations.removeValue(forKey: id)
            }
        }

        return stream
    }

    /// Broadcasts a value to all current subscribers.
    public func send(_ value: Element) {
        let snapshot = storage.read { state in
            state.isFinished ? [:] : state.continuations
        }
        guard !snapshot.isEmpty else { return }

        var terminated: [UUID] = []
        for (id, continuation) in snapshot {
            if case .terminated = continuation.yield(value) {
                terminated.append(id)
            }
        }

        if !terminated.isEmpty {
            storage.write { state in
                for id in terminated {
                    state.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Finishes the channel and all existing subscribers.
    public func finish() {
        // We take a snapshot first so we can release the lock and then finish each stream outside the critical section.
        // That avoids holding the lock while running user code and ensures every subscriber is actually completed.
        let continuations = storage.write { state -> [AsyncStream<Element>.Continuation] in
            if state.isFinished {
                return []
            }
            state.isFinished = true
            let snapshot = Array(state.continuations.values)
            state.continuations.removeAll()
            return snapshot
        }

        for continuation in continuations {
            continuation.finish()
        }
    }
}
