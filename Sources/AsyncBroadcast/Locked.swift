import os

public struct Locked<Value>: Sendable {
    // Uses os_unfair_lock under the hood. It's not a recursive lock.
    // Attempting to lock it again from the same thread while the lock is already locked will crash.
    let value: OSAllocatedUnfairLock<Value>

    public init(value: consuming Value) {
        self.value = OSAllocatedUnfairLock(uncheckedState: value)
    }

    @discardableResult
    public func write<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        try value.withLockUnchecked(body)
    }

    @discardableResult
    public func read<R>(_ body: (Value) throws -> R) rethrows -> R {
        try value.withLockUnchecked { try body($0) }
    }
}
