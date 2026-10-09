import XCTest
@testable import InteraMusic

final class TradingDashboardTests: XCTestCase {
    func testTradingNavigationRequiresHTTPSWithoutCredentialsOrCustomPorts() {
        XCTAssertTrue(TradingNavigationPolicy.allows(URL(string: "https://trade.jiza.app")!))
        XCTAssertTrue(TradingNavigationPolicy.allows(URL(string: "https://login.example.com/path")!))
        XCTAssertFalse(TradingNavigationPolicy.allows(URL(string: "http://trade.jiza.app")!))
        XCTAssertFalse(TradingNavigationPolicy.allows(URL(string: "https://user:password@trade.jiza.app")!))
        XCTAssertFalse(TradingNavigationPolicy.allows(URL(string: "https://trade.jiza.app:8443")!))
    }
}
