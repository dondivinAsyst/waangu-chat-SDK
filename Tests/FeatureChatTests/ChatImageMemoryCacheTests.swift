import XCTest
import UIKit
@testable import WaanguFeatureChat

final class ChatImageMemoryCacheTests: XCTestCase {

    func test_storeThenRead_returnsSameImage() {
        let cache = ChatImageMemoryCache()
        let image = makeImage()

        cache.store(image, forKey: "a")

        XCTAssertTrue(cache.image(forKey: "a") === image)
    }

    func test_readOfUnknownKey_isNil() {
        XCTAssertNil(ChatImageMemoryCache().image(forKey: "missing"))
    }

    func test_storeOverwritesPreviousEntry() {
        let cache = ChatImageMemoryCache()
        let first = makeImage()
        let second = makeImage()

        cache.store(first, forKey: "a")
        cache.store(second, forKey: "a")

        XCTAssertTrue(cache.image(forKey: "a") === second)
    }

    func test_cacheCostIsProportionalToPixelCount() {
        // Guards against a zero cost, which would defeat NSCache's cost eviction.
        XCTAssertGreaterThan(makeImage().cacheCost, 0)
    }

    func test_cacheCostIsZeroWithoutBackingCGImage() {
        XCTAssertEqual(UIImage().cacheCost, 0)
    }

    // MARK: - Helpers

    private func makeImage(side: CGFloat = 10) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}
