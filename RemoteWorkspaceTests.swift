import XCTest
@testable import Jiza

final class RemoteWorkspaceTests: XCTestCase {
    func testSavedGatewaysRequireHTTPSAndExcludeCredentialsAndTokens() {
        XCTAssertEqual(RemoteWorkspacePolicy.gateway(" https://node.example/terminal/ ")?.host, "node.example")
        for value in ["http://node.example", "ssh://node.example", "file:///tmp/test", "https://user:pass@node.example", "https://node.example?token=secret", "https://node.example/#secret", "https://"] {
            XCTAssertNil(RemoteWorkspacePolicy.gateway(value), value)
        }
    }

    func testDesktopClientKeyIsEncodedAsAFragment() throws {
        let url = try XCTUnwrap(RemoteWorkspacePolicy.desktopURL(gateway: "https://node.example/guacamole/", clientKey: "MQBjAHBvc3RncmVzcWw="))
        XCTAssertEqual(url.host, "node.example")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.path, "/guacamole/")
        XCTAssertEqual(url.fragment, "/client/MQBjAHBvc3RncmVzcWw=")
        XCTAssertNil(RemoteWorkspacePolicy.desktopURL(gateway: "https://node.example/", clientKey: ""))
        XCTAssertNil(RemoteWorkspacePolicy.desktopURL(gateway: "https://node.example/", clientKey: "../invalid#link"))
    }

    func testRemoteNavigationBlocksInsecureAndCustomSchemes() {
        XCTAssertTrue(RemoteWorkspacePolicy.allowsNavigation(URL(string: "https://login.example/path#session")!))
        for value in ["http://node.example", "javascript:alert(1)", "file:///tmp/test", "https://user:password@node.example"] {
            XCTAssertFalse(RemoteWorkspacePolicy.allowsNavigation(URL(string: value)!), value)
        }
    }
}
