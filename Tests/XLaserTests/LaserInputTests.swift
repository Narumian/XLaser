import XCTest
import XLaser

final class LaserInputTests: XCTestCase {
    func testInvalidMediaAndMatrixAreRejected() {
        XCTAssertThrowsError(try LaserInputImage(width: 2, height: 1, rgba: [0]))
        XCTAssertThrowsError(try LaserInputImage(width: Int.max, height: 2, rgba: []))
        XCTAssertThrowsError(try LaserInputAudio(sampleRate: 0, channels: 1, samples: []))
        XCTAssertThrowsError(try LaserInputAudio(sampleRate: 48000, channels: 2, samples: [0]))
        XCTAssertThrowsError(try LaserInputSpectrum(sampleRate: 48000, fftSize: 8, bins: [.nan]))
        XCTAssertThrowsError(try LaserInputMatrix(rows: 2, columns: 2, values: [1]))
    }
}
