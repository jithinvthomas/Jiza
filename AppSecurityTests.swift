import XCTest
import UIKit
@testable import InteraMusic

private final class MemoryLockStorage: LockStorage {
    var value = LockRecord()
    var failWrites = false
    func read() throws -> LockRecord { value }
    func write(_ record: LockRecord) throws {
        if failWrites { throw LockError.message("Storage unavailable") }
        value = record
    }
}

@MainActor
final class AppSecurityTests: XCTestCase {
    func testPINIsSaltedAndRejectsWrongValues() throws {
        let first = try BrowserPIN.create("123456")
        let second = try BrowserPIN.create("123456")
        XCTAssertNotEqual(first.salt, second.salt)
        XCTAssertNotEqual(first.digest, second.digest)
        XCTAssertTrue(try first.matches("123456"))
        XCTAssertFalse(try first.matches("654321"))
        XCTAssertFalse(try first.matches("12345"))
        XCTAssertFalse(BrowserPIN.valid("abcdef"))
    }
    func testPINLockoutSurvivesRelaunchAndExpires() async throws {
        let store = MemoryLockStorage()
        var clock = Date()
        let security = AppSecurity(storage: store, now: { clock }, authenticate: { _ in true })
        let saved = await security.setPIN("123456", confirmation: "123456")
        XCTAssertTrue(saved)
        security.lock(); security.browserVisible = true
        for _ in 0..<5 { await security.unlockBrowser("000000") }
        XCTAssertTrue(security.needsBrowserUnlock)
        XCTAssertEqual(store.value.failures, 5)
        let restored = AppSecurity(storage: store, now: { clock }, authenticate: { _ in true })
        restored.browserVisible = true
        await restored.unlockBrowser("123456")
        XCTAssertFalse(restored.browserUnlocked)
        clock = clock.addingTimeInterval(31)
        await restored.unlockBrowser("123456")
        XCTAssertTrue(restored.browserUnlocked)
        XCTAssertEqual(store.value.failures, 0)
        restored.lock()
        XCTAssertFalse(restored.browserUnlocked)
    }
    func testAuthenticationFailureCannotEnableDisableOrResetLocks() async throws {
        let store = MemoryLockStorage()
        store.value.appLock = true
        store.value.pin = try BrowserPIN.create("123456")
        let security = AppSecurity(storage: store, authenticate: { _ in false })
        await security.unlockApp()
        XCTAssertTrue(security.needsAppUnlock)
        await security.setAppLock(false)
        XCTAssertTrue(store.value.appLock)
        let removed = await security.removePIN()
        XCTAssertFalse(removed)
        XCTAssertNotNil(store.value.pin)
    }
    func testFailedKeychainWriteNeverUnlocksPIN() async throws {
        let store = MemoryLockStorage()
        store.value.pin = try BrowserPIN.create("123456")
        store.failWrites = true
        let security = AppSecurity(storage: store, authenticate: { _ in true })
        await security.unlockBrowser("123456")
        XCTAssertFalse(security.browserUnlocked)
    }
    func testPrivacyWindowCoversPresentedScreensUntilAuthentication() async throws {
        let store = MemoryLockStorage(); store.value.appLock = true
        let security = AppSecurity(storage: store, authenticate: { _ in true })
        let host = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow })
        let coordinator = SecurityShieldWindow.Coordinator(security: security)
        coordinator.attach(host)
        defer { coordinator.window?.isHidden = true; host.makeKey() }
        XCTAssertFalse(try XCTUnwrap(coordinator.window).isHidden)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.window).windowLevel.rawValue, UIWindow.Level.normal.rawValue)
        XCTAssertTrue(coordinator.window?.rootViewController?.view.accessibilityViewIsModal == true)
        await security.unlockApp(); coordinator.refresh()
        XCTAssertTrue(coordinator.window?.isHidden == true)
        security.obscured = true; coordinator.refresh()
        XCTAssertFalse(coordinator.window?.isHidden == true)
        security.lock(); security.obscured = false; coordinator.refresh()
        XCTAssertFalse(coordinator.window?.isHidden == true)
    }
}
