import Playgrounds
import Combine
import Foundation

#Playground("Simple example of the broadcast") {
    // Combine Example
    let subject = PassthroughSubject<String, Never>()
    var cancellables = Set<AnyCancellable>()

    subject
        .sink { value in
            print("Combine A got \(value)")
        }
        .store(in: &cancellables)

    subject
        .sink { value in
            print("Combine B got \(value)")
        }
        .store(in: &cancellables)

    subject.send("hello")
    subject.send("world")
    subject.send(completion: .finished)

    // Swift Concurrency counterpart
    let channel = AsyncBroadcast<String>()

    Task {
        let stream = channel.makeStream()
        for await value in stream {
            print("Concurrency A got \(value)")
        }
    }

    Task {
        let stream = channel.makeStream()
        for await value in stream {
            print("Concurrency B got \(value)")
        }
    }

    Task {
        channel.send("hello")
        channel.send("world")
        channel.finish()
    }
}

#Playground("Cancellation of the broadcast") {
    // Combine Example
    let subject = PassthroughSubject<Int, Never>()
    let cancellable = subject.sink { value in
        print("Combine received \(value)")
    }

    subject.send(1)
    cancellable.cancel()
    subject.send(2)
    subject.send(completion: .finished)

    // Swift Concurrency counterpart

    let channel = AsyncBroadcast<Int>()

    let task = Task {
        let stream = channel.makeStream()
        for await value in stream {
            print("Concurrency received \(value)")
        }
    }

    await Task.yield()
    channel.send(1)
    task.cancel()
    // there's no backpressure, we may get all the values if we don't sleep here, because of how the race conditions and cancellation
    try? await Task.sleep(for: .milliseconds(10))
    channel.send(2)
    channel.send(3)
    channel.send(4)
}

#Playground("ViewModel") {

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
}
