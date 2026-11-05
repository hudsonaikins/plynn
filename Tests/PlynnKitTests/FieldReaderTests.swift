import XCTest
@testable import PlynnKit

final class FieldReaderTests: XCTestCase {
    func testPastePreflightOnlyAcceptsEditableAndNonSecureTargets() {
        XCTAssertTrue(FieldReader.acceptsPaste(
            role: "AXTextArea", valueIsSettable: false, secure: false, bundleID: "com.apple.Terminal"))
        XCTAssertTrue(FieldReader.acceptsPaste(
            role: "AXUnknown", valueIsSettable: true, secure: false, bundleID: nil))
        XCTAssertFalse(FieldReader.acceptsPaste(
            role: "AXTextArea", valueIsSettable: false, secure: false, bundleID: "com.apple.TextEdit"))
        XCTAssertFalse(FieldReader.acceptsPaste(
            role: "AXWebArea", valueIsSettable: false, secure: false, bundleID: "com.apple.Terminal"))
        XCTAssertFalse(FieldReader.acceptsPaste(
            role: "AXGroup", valueIsSettable: false, secure: false, bundleID: nil))
        XCTAssertFalse(FieldReader.acceptsPaste(
            role: "AXTextArea", valueIsSettable: true, secure: true, bundleID: "com.apple.Terminal"))
    }
}
