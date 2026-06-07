import XCTest
@testable import ClipShot

final class DynamicMeshCacheTests: XCTestCase {

    func test_meshImage_returnsCanonicalSize() throws {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1),
            size: CGSize(width: 80, height: 60))
        let out = try XCTUnwrap(DynamicMeshCache.shared.meshImage(for: img, selection: .null))
        XCTAssertEqual(out.width, 512)
        XCTAssertEqual(out.height, 512)
    }

    func test_meshImage_sameKeyReturnsIdenticalInstance() throws {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1),
            size: CGSize(width: 80, height: 60))
        let a = try XCTUnwrap(DynamicMeshCache.shared.meshImage(for: img, selection: .null))
        let b = try XCTUnwrap(DynamicMeshCache.shared.meshImage(for: img, selection: .null))
        XCTAssertTrue(a === b, "cache should return the same CGImage for the same key")
    }
}
