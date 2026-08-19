import XCTest
@testable import ReelForgeCore

final class CaptionCatalogTests: XCTestCase {
    func testCatalogHasThirtyRequiredStyles() throws {
        let styles = try CaptionCatalog.load()
        XCTAssertGreaterThanOrEqual(styles.count, 30)
        let ids = Set(styles.map(\.id))
        for required in CaptionCatalog.requiredIDs {
            XCTAssertTrue(ids.contains(required), required)
        }
        XCTAssertEqual(CaptionCatalog.defaultID(forPreset: "viral-hook"), "dynamic-minimal")
        let look = CaptionCatalog.look(id: "hormozi-classic")
        XCTAssertEqual(look.highlight.uppercased(), "#F7C204")
        XCTAssertEqual(look.asCaptionStyle().animation, .pop)
    }
}
