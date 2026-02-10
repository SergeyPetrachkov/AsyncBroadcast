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
