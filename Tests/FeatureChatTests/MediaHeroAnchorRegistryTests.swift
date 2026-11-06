import XCTest
import UIKit
@testable import WaanguFeatureChat

@MainActor
final class MediaHeroAnchorRegistryTests: XCTestCase {

    func test_registerThenLookup_returnsRectAndImage() {
        let registry = MediaHeroAnchorRegistry()
        let image = UIImage()
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)

        registry.register(id: "a", rect: rect, image: image, sourceView: nil)

        XCTAssertEqual(registry.anchor(for: "a")?.rect, rect)
        XCTAssertTrue(registry.anchor(for: "a")?.image === image)
    }

    func test_registerTwice_overwritesRect() {
        // Bubbles re-report as the list scrolls; the newest rect wins.
        let registry = MediaHeroAnchorRegistry()
        registry.register(id: "a", rect: .zero, image: nil, sourceView: nil)
        registry.register(id: "a", rect: CGRect(x: 1, y: 1, width: 1, height: 1), image: nil, sourceView: nil)

        XCTAssertEqual(registry.anchor(for: "a")?.rect, CGRect(x: 1, y: 1, width: 1, height: 1))
    }

    func test_unregister_removesAnchor() {
        let registry = MediaHeroAnchorRegistry()
        registry.register(id: "a", rect: .zero, image: nil, sourceView: nil)
        registry.unregister(id: "a")

        XCTAssertNil(registry.anchor(for: "a"))
    }

    func test_lookupOfUnknownID_isNil() {
        XCTAssertNil(MediaHeroAnchorRegistry().anchor(for: "nope"))
    }

    func test_sourceViewIsHeldWeakly() {
        // A recycled cell must not be retained by the registry.
        let registry = MediaHeroAnchorRegistry()
        autoreleasepool {
            let view = UIView()
            registry.register(id: "a", rect: .zero, image: nil, sourceView: view)
            XCTAssertNotNil(registry.anchor(for: "a")?.sourceView)
        }
        XCTAssertNil(registry.anchor(for: "a")?.sourceView)
    }

    func test_hiddenAnchorIDDefaultsToNil() {
        XCTAssertNil(MediaHeroAnchorRegistry().hiddenAnchorID)
    }
}
