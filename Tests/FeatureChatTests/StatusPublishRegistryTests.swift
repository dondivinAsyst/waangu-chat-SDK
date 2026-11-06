import XCTest
@testable import WaanguFeatureChat

/// A status being published must not be published a second time while the
/// first attempt is still in flight — that second POST is what the backend
/// rejected, and its failure overwrote the first one's success.
final class StatusPublishRegistryTests: XCTestCase {

    /// Lets a test hold the first publish open until it has tried the second.
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false
        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    func test_aSecondPublishOfTheSameStatusIsSkippedWhileTheFirstIsInFlight() async {
        let registry = StatusPublishRegistry()
        let gate = Gate()
        let posts = Counter()

        let first = Task {
            await registry.run(for: "story-1") {
                await posts.increment()
                await gate.wait()
            }
        }
        // Wait until the first publish has claimed the id.
        while await !registry.isRunning("story-1") { await Task.yield() }

        let second = await registry.run(for: "story-1") {
            await posts.increment()
        }

        await gate.open()
        let firstRan = await first.value

        XCTAssertTrue(firstRan)
        XCTAssertFalse(second, "the resume must skip a status already being published")
        let count = await posts.value
        XCTAssertEqual(count, 1, "exactly one POST")
    }

    func test_differentStatusesPublishIndependently() async {
        let registry = StatusPublishRegistry()
        let gate = Gate()

        let first = Task { await registry.run(for: "story-1") { await gate.wait() } }
        while await !registry.isRunning("story-1") { await Task.yield() }

        let other = await registry.run(for: "story-2") {}

        await gate.open()
        _ = await first.value
        XCTAssertTrue(other)
    }

    /// After a publish ends — including an app restart, where nothing is in
    /// flight — an interrupted status can be resumed.
    func test_theIdIsReleasedOnceThePublishEnds() async {
        let registry = StatusPublishRegistry()
        _ = await registry.run(for: "story-1") {}

        let again = await registry.run(for: "story-1") {}
        XCTAssertTrue(again)
        let running = await registry.isRunning("story-1")
        XCTAssertFalse(running)
    }

    func test_theIdIsReleasedEvenWhenThePublishThrows() async {
        struct Boom: Error {}
        let registry = StatusPublishRegistry()

        do {
            _ = try await registry.run(for: "story-1") { throw Boom() }
            XCTFail("expected the error to propagate")
        } catch {
            XCTAssertTrue(error is Boom)
        }

        let running = await registry.isRunning("story-1")
        XCTAssertFalse(running, "a failed publish must not block a later retry")
    }
}
