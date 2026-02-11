# AsyncBroadcast

A tiny 1-to-N broadcast channel built on Swift Concurrency. It lets multiple subscribers receive the same values without Combine.

## What this provides

- A thread-safe broadcast channel: `AsyncBroadcast<Element>`.
- A per-subscriber `AsyncStream` created via `makeStream()`.
- Explicit channel completion via `finish()`.
- Optional buffering control per subscriber or per channel.

## Requirements

- Swift 6.2 or newer.
- `Element` must conform to `Sendable`.

## Quick start

```swift
import AsyncBroadcast

let channel = AsyncBroadcast<String>()

Task {
    let stream = channel.makeStream()
    for await message in stream {
        print("received: \(message)")
    }
    print("stream finished")
}

Task {
    channel.send("hello")
    channel.send("world")
    channel.finish()
}
```

## How it works

`AsyncBroadcast` keeps a list of `AsyncStream` continuations. Each call to `makeStream()` registers a new continuation. 
Calling `send(_:)` yields the value to all current continuations.
Calling `finish()` completes the channel and ends all active streams.
If the caller task is already cancelled, `makeStream()` returns a finished stream.

## Examples

### 1) Multiple subscribers (1-to-N broadcast)

```swift
import AsyncBroadcast

let channel = AsyncBroadcast<Int>()

Task {
    let streamA = channel.makeStream()
    for await value in streamA {
        print("A got \(value)")
    }
}

Task {
    let streamB = channel.makeStream()
    for await value in streamB {
        print("B got \(value)")
    }
}

Task {
    for i in 1...3 {
        channel.send(i)
    }
    channel.finish()
}
```

Expected output (order may vary between A and B but values are identical):

```
A got 1
B got 1
A got 2
B got 2
A got 3
B got 3
```

or more iOS friendly sample:

```swift
    enum AppEvent: Sendable {
        case message(String)
    }

    final class EventService: Sendable {
        let events = AsyncBroadcast<AppEvent>()

        func startEmitting() {
            Task.detached {
                for i in 1...5 {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    self.events.send(.message("event-\(i)"))
                }
                self.events.finish()
            }
        }
    }

    @MainActor
    final class FeedViewModel: ObservableObject {
        @Published var messages: [String] = []
        private let service: EventService
        private var task: Task<Void, Never>?

        init(service: EventService) {
            self.service = service
            subscribe()
        }

        private func subscribe() {
            let stream = service.events.makeStream()
            task = Task { [weak self] in
                for await event in stream {
                    if case let .message(text) = event {
                        self?.messages.append("Feed: \(text)")
                    }
                }
            }
        }

        deinit {
            task?.cancel()
        }
    }

    @MainActor
    final class LoggerViewModel: ObservableObject {
        @Published var logs: [String] = []
        private let service: EventService
        private var task: Task<Void, Never>?

        init(service: EventService) {
            self.service = service
            subscribe()
        }

        private func subscribe() {
            let stream = service.events.makeStream()
            task = Task { [weak self] in
                for await event in stream {
                    if case let .message(text) = event {
                        self?.logs.append("Log: \(text)")
                    }
                }
            }
        }

        deinit {
            task?.cancel()
        }
    }

    let service = EventService()
    let feedVM = FeedViewModel(service: service)
    let loggerVM = LoggerViewModel(service: service)

    service.startEmitting()
```

### 2) Independent subscriber lifetimes

Each subscriber can stop consuming without affecting others. The channel cleans
up terminated subscribers automatically.

```swift
import AsyncBroadcast

let channel = AsyncBroadcast<String>()

let taskA = Task {
    let streamA = channel.makeStream()
    var iterator = streamA.makeAsyncIterator()
    _ = await iterator.next() // receive one value
    // stop early by exiting the task
}

Task {
    let streamB = channel.makeStream()
    for await value in streamB {
        print("B got \(value)")
    }
}

Task {
    channel.send("first")
    channel.send("second")
    channel.finish()
}

_ = await taskA.result
```

### 3) Buffering control

You can set a default buffer size for all subscribers, or override it per
subscription.

```swift
import AsyncBroadcast

// Keep at most 10 newest values per subscriber.
let channel = AsyncBroadcast<Int>(bufferingPolicy: .bufferingNewest(10))

Task {
    // Override for a specific subscriber.
    let slowStream = channel.makeStream(bufferingPolicy: .bufferingOldest(3))
    for await value in slowStream {
        print("slow subscriber got \(value)")
        try? await Task.sleep(nanoseconds: 200_000_000)
    }
}

Task {
    for i in 1...20 {
        channel.send(i)
    }
    channel.finish()
}
```

### 4) Fan-out from a producer task

This is a common pattern when you want to broadcast events from a single source.

```swift
import AsyncBroadcast

let channel = AsyncBroadcast<String>()

Task {
    let stream = channel.makeStream()
    for await event in stream {
        print("UI subscriber: \(event)")
    }
}

Task {
    let stream = channel.makeStream()
    for await event in stream {
        print("Logging subscriber: \(event)")
    }
}

Task {
    for i in 1...5 {
        channel.send("event-\(i)")
    }
    channel.finish()
}

```

## Thread safety and Sendable

`AsyncBroadcast` is safe to use from multiple tasks. The channel stores subscriber continuations inside a lock-protected state container and only requires `Element: Sendable` to avoid data races.

## Memory management

- Each subscriber is removed when its `AsyncStream` terminates, so the channel does not keep stale continuations.
- `finish()` ends all active streams and releases their continuations.
- The termination handler captures the channel weakly to avoid reference cycles between the channel and the stored continuations.

## Implementation notes

- The channel keeps state in a lock-protected container to allow synchronous `send`, `finish`, and `makeStream` without actor hops.
- Continuations are finished and yielded outside the lock to avoid reentrancy and to prevent holding the lock while user code runs.
- The lock is non-recursive; re-entrance on the same thread will probably crash.

```swift
let locked = Locked(value: 0)
locked.withCriticalRegion { _ in
    locked.withCriticalRegion { _ in } // reentrant on same thread -> probable crash
}
```

## Notes and limitations

- New subscribers only receive values sent after they subscribe.
- Once finished, the channel cannot be reopened.
- If a subscriber is too slow, values may be dropped depending on the buffer policy.
- Creating a stream without consuming it keeps the subscription until it is deinitialized or the channel finishes.

## Building and Testing

Run:

```
swift build
swift test
```
