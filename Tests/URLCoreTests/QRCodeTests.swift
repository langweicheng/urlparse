import XCTest
import CoreImage
@testable import URLCore

final class QRCodeTests: XCTestCase {
    func testDecodesBackToExactURL() throws {
        let url = "imeituan://www.meituan.com/mrn?city=%E5%8C%97%E4%BA%AC&date=2026-10-01#detail"
        let image = try QRCode.image(for: url)
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
        let codes = detector.features(in: CIImage(cgImage: image)) as! [CIQRCodeFeature]
        XCTAssertEqual(codes.first?.messageString, url)
    }
    func testRejectsEmptyAndOversizedInput() {
        XCTAssertThrowsError(try QRCode.image(for: ""))
        XCTAssertThrowsError(try QRCode.image(for: String(repeating: "a", count: 2954)))
    }
}
