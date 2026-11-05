import XCTest
@testable import PlynnKit

@MainActor
final class PermissionsTests: XCTestCase {
    func testSetupIsOnlyForMissingPermissions() {
        XCTAssertFalse(Permissions.needsSetup(micGranted: true, accessibilityGranted: true))
        XCTAssertTrue(Permissions.needsSetup(micGranted: false, accessibilityGranted: true))
        XCTAssertTrue(Permissions.needsSetup(micGranted: true, accessibilityGranted: false))
        XCTAssertTrue(Permissions.needsSetup(micGranted: false, accessibilityGranted: false))
    }
}
