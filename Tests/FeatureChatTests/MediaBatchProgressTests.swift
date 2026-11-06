import XCTest
@testable import WaanguFeatureChat

/// A batch of media is one operation to the person watching it, so it gets one
/// bar. The control used to read a single item's slot, so sending five photos ran
/// the ring from empty to full five times over.
final class MediaBatchProgressTests: XCTestCase {

    // MARK: - Aggregate progress

    /// The case that was reported: three equal items, the first done and the
    /// second half way. One bar reads half of the batch, not half of item two.
    func test_progressSpansTheWholeBatch() {
        let state = MediaBatchProgress.combine([
            (1, .done),
            (1, .active(0.5)),
            (1, .idle)
        ])

        XCTAssertEqual(state, .transferring(progress: 0.5))
    }

    /// Bytes, not items: a 4 MB video must not advance the bar as fast as a
    /// 200 KB photo.
    func test_progressIsWeightedByBytes() {
        let state = MediaBatchProgress.combine([
            (200_000, .done),
            (3_800_000, .active(0.5))
        ])

        // 200k + 1.9M of 4M
        XCTAssertEqual(progressValue(of: state) ?? 0, 0.525, accuracy: 0.0001)
    }

    func test_everythingDoneIsSuccess() {
        XCTAssertEqual(MediaBatchProgress.combine([(1, .done), (1, .done)]), .success)
    }

    func test_nothingStartedIsIdle() {
        XCTAssertEqual(MediaBatchProgress.combine([(1, .idle), (1, .idle)]), .idle)
    }

    func test_emptyBatchIsIdle() {
        XCTAssertEqual(MediaBatchProgress.combine([]), .idle)
    }

    /// A bar pinned at zero reads as stuck; an indeterminate spinner is honest
    /// about having started but not yet moved.
    func test_startedButUnmovedIsLoading() {
        XCTAssertEqual(MediaBatchProgress.combine([(1, .active(0)), (1, .idle)]), .loading)
    }

    // MARK: - Failure

    /// A failure is the only state the user can act on, so it must not hide behind
    /// siblings that are merely idle.
    func test_aFailureIsReportedWhenNothingIsRunning() {
        let state = MediaBatchProgress.combine([
            (1, .done),
            (1, .failed("boom")),
            (1, .idle)
        ])

        XCTAssertEqual(state, .failure(error: "boom"))
    }

    /// While anything is still moving the batch is still working — the bar keeps
    /// going and the failed item is picked up once it stops.
    func test_progressOutranksAFailureWhileSomethingRuns() {
        let state = MediaBatchProgress.combine([
            (1, .failed("boom")),
            (1, .active(0.5))
        ])

        XCTAssertEqual(state, .transferring(progress: 0.25))
    }

    /// A failed item contributes nothing, so the bar cannot claim a batch is
    /// complete when part of it never arrived.
    func test_aFailedItemNeverCountsAsMoved() {
        let state = MediaBatchProgress.combine([
            (1, .failed("boom")),
            (1, .active(1.0))
        ])

        XCTAssertEqual(state, .transferring(progress: 0.5))
    }

    // MARK: - Sample mapping

    func test_uploadStatesMapToSamples() {
        XCTAssertEqual(MediaBatchProgress.sample(upload: .loading), .active(0))
        XCTAssertEqual(MediaBatchProgress.sample(upload: .uploading(progress: 0.3)), .active(0.3))
        XCTAssertEqual(MediaBatchProgress.sample(upload: .success(url: "u")), .done)
        XCTAssertEqual(MediaBatchProgress.sample(upload: .failure(error: "e")), .failed("e"))
        XCTAssertEqual(MediaBatchProgress.sample(upload: nil), .idle)
    }

    func test_downloadStatesMapToSamples() {
        XCTAssertEqual(MediaBatchProgress.sample(download: .downloading(progress: 0.3)), .active(0.3))
        XCTAssertEqual(MediaBatchProgress.sample(download: .success), .done)
        XCTAssertEqual(MediaBatchProgress.sample(download: .failure(error: "e")), .failed("e"))
        XCTAssertEqual(MediaBatchProgress.sample(download: nil), .idle)
    }

    // MARK: - Helper

    private func progressValue(of state: MediaTransferState) -> Double? {
        guard case .transferring(let progress) = state else { return nil }
        return progress
    }
}
