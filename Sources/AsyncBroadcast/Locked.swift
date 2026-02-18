import os

/// A minimal, non-recursive unfair lock wrapper for protecting in-process state.
///
/// Access the protected value only inside `withCriticalRegion`.
struct Locked<Value>: Sendable, ~Copyable {
    // Uses os_unfair_lock under the hood. It's not a recursive lock.
    // Attempting to lock it again from the same thread while the lock is already locked will crash.
    private let value: OSAllocatedUnfairLock<Value>

    /// Creates a new lock guarding the provided value.
    init(value: consuming sending Value) {
        self.value = OSAllocatedUnfairLock(uncheckedState: value)
    }

    /// Executes `body` while holding the lock and returns its result.
    ///
    /// Do not call across an `await` and do not re-enter from the same thread.
    @discardableResult
    borrowing func withCriticalRegion<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        try value.withLockUnchecked(body)
    }
}
