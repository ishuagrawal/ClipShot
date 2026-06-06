import XCTest
@testable import ClipShot

final class DynamicMeshCacheTests: XCTestCase {

    func test_meshImage_returnsRequestedSize() throws {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1),
            size: CGSize(width: 80, height: 60))
        let out = try XCTUnwrap(DynamicMeshCache.shared.meshImage(
            for: img, selection: .null, size: CGSize(width: 40, height: 30)))
        XCTAssertEqual(out.width, 40)
        XCTAssertEqual(out.height, 30)
    }

    func test_meshImage_sameKeyReturnsIdenticalInstance() throws {
        let img = FixtureDocument.makeSolidImage(
            color: CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1),
            size: CGSize(width: 80, height: 60))
        let a = try XCTUnwrap(DynamicMeshCache.shared.meshImage(
            for: img, selection: .null, size: CGSize(width: 40, height: 30)))
        let b = try XCTUnwrap(DynamicMeshCache.shared.meshImage(
            for: img, selection: .null, size: CGSize(width: 40, height: 30)))
        XCTAssertTrue(a === b, "cache should return the same CGImage for the same key")
    }
}
