import AsyncBroadcast
import Testing

struct AsyncBroadcastTests {

    @Test(.timeLimit(.minutes(1)))
    func broadcastsToMultipleSubscribers() async {
        let channel = AsyncBroadcast<Int>()
        let stream1 = channel.makeStream()
        let stream2 = channel.makeStream()

        var iterator1 = stream1.makeAsyncIterator()
        var iterator2 = stream2.makeAsyncIterator()

        async let value1 = iterator1.next()
        async let value2 = iterator2.next()

        channel.send(42)

        #expect(await value1 == 42)
        #expect(await value2 == 42)

        channel.finish()

        #expect(await iterator1.next() == nil)
        #expect(await iterator2.next() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func finishesNewSubscribersImmediately() async {
        let channel = AsyncBroadcast<Int>()

        channel.finish()

        let stream = channel.makeStream()
        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func terminatedSubscriberStopsReceiving() async {
        let channel = AsyncBroadcast<Int>()

        let streamA = channel.makeStream()
        let streamB = channel.makeStream()

        let taskA = Task {
            var iterator = streamA.makeAsyncIterator()
            return await iterator.next()
        }

        var iteratorB = streamB.makeAsyncIterator()

        channel.send(1)

        #expect(await taskA.value == 1)
        #expect(await iteratorB.next() == 1)

        channel.send(2)
        #expect(await iteratorB.next() == 2)

        channel.finish()
        #expect(await iteratorB.next() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func sendAfterFinishDoesNotDeliver() async {
        let channel = AsyncBroadcast<Int>()
        let stream = channel.makeStream()
        var iterator = stream.makeAsyncIterator()

        channel.finish()
        channel.send(99)

        #expect(await iterator.next() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func lateSubscriberDoesNotReceivePastValues() async {
        let channel = AsyncBroadcast<Int>()

        channel.send(1)

        let stream = channel.makeStream()
        var iterator = stream.makeAsyncIterator()

        channel.send(2)
        #expect(await iterator.next() == 2)

        channel.finish()
        #expect(await iterator.next() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesSendOrderPerSubscriber() async {
        let channel = AsyncBroadcast<Int>()
        let stream = channel.makeStream()

        async let collected = collectValues(from: stream, expectedCount: 3)

        channel.send(1)
        channel.send(2)
        channel.send(3)
        channel.finish()

        #expect(await collected == [1, 2, 3])
    }

    @Test(.timeLimit(.minutes(1)))
    func bufferingNewestDropsOldValues() async {
        let channel = AsyncBroadcast<Int>(bufferingPolicy: .bufferingNewest(2))
        let stream = channel.makeStream()

        channel.send(1)
        channel.send(2)
        channel.send(3)
        channel.finish()

        let values = await collectValues(from: stream, expectedCount: 3)
        #expect(values == [2, 3])
    }

    @Test(.timeLimit(.minutes(1)))
    func bufferingOldestDropsNewValues() async {
        let channel = AsyncBroadcast<Int>(bufferingPolicy: .bufferingOldest(2))
        let stream = channel.makeStream()

        channel.send(1)
        channel.send(2)
        channel.send(3)
        channel.finish()

        let values = await collectValues(from: stream, expectedCount: 3)
        #expect(values == [1, 2])
    }

    private func collectValues<T: Sendable>(
        from stream: AsyncStream<T>,
        expectedCount: Int
    ) async -> [T] {
        var result: [T] = []
        var iterator = stream.makeAsyncIterator()
        while result.count < expectedCount {
            guard let value = await iterator.next() else { break }
            result.append(value)
        }
        return result
    }
}
