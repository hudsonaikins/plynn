import XCTest
@testable import PlynnKit

final class AsyncTimeoutTests: XCTestCase {
    /// The deadline must win even when the operation ignores cancellation.
    func testTimeoutFiresWhileOperationIgnoresCancellation() async {
        let clock = ContinuousClock()
        var result: String?
        let elapsed = await clock.measure {
            result = await withTaskTimeout(seconds: 0.3) {
                await withUnsafeContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                        continuation.resume(returning: "too late")
                    }
                }
            }
        }
        XCTAssertNil(result, "timeout should discard a late result")
        XCTAssertLessThan(elapsed, .seconds(1.5))
    }

    func testTimeoutReturnsValueWhenOperationBeatsDeadline() async {
        let result = await withTaskTimeout(seconds: 5) { "on time" }
        XCTAssertEqual(result, "on time")
    }
}
