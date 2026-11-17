import XCTest
import WebKit
@testable import Jiza

final class RemoteWorkspaceTests: XCTestCase {
    func testTerminalAcceptsOnlySafeGuacamoleConnectionFragments() {
        XCTAssertNotNil(RemoteWorkspacePolicy.terminalURL("https://node.example/guacamole/#/client/MQBjAHBvc3RncmVzcWw="))
        XCTAssertNotNil(RemoteWorkspacePolicy.terminalURL("https://node.example/terminal/"))
        for value in ["https://node.example/#token=secret", "https://node.example/?token=secret#/client/MQ==", "https://user:password@node.example/#/client/MQ==", "http://node.example/#/client/MQ==", "https://node.example/#/client/../invalid"] {
            XCTAssertNil(RemoteWorkspacePolicy.terminalURL(value), value)
        }
    }

    @MainActor
    func testGuacamoleInputUsesTheGatewayControlsAndRejectsOtherPages() async throws {
        let web = WKWebView()
        web.loadHTMLString("""
        <div class="client-view"></div>
        <script>
        location.hash = '/client/fixture';
        window.angular = {element: () => ({injector: () => ({get: () => ({
          $evalAsync: fn => fn(),
          $broadcast: name => {
            if (name !== 'guacShowMenu' || document.getElementById('relative')) return;
            for (const id of ['ime-osk', 'ime-none', 'relative', 'absolute']) {
              const input = document.createElement('input'); input.type = 'radio'; input.id = id;
              input.name = id.startsWith('ime-') ? 'keyboard' : 'pointer'; document.body.append(input);
            }
          }
        })})})};
        </script>
        """, baseURL: URL(string: "https://gateway.example/"))
        for _ in 0..<50 {
            if (try? await web.evaluateJavaScript("Boolean(window.angular)")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        for id in ["relative", "keyboard"] {
            let result = try await web.callAsyncJavaScript(RemoteWorkspaceInput.script, arguments: ["inputID": id], in: nil, in: .page)
            XCTAssertEqual(result as? Bool, true)
        }
        let checked = try await web.evaluateJavaScript("document.getElementById('relative').checked && document.getElementById('ime-osk').checked")
        XCTAssertEqual(checked as? Bool, true)
        _ = try await web.callAsyncJavaScript(RemoteWorkspaceInput.script, arguments: ["inputID": "keyboard"], in: nil, in: .page)
        let hidden = try await web.evaluateJavaScript("document.getElementById('ime-none').checked")
        XCTAssertEqual(hidden as? Bool, true)
        _ = try await web.evaluateJavaScript("location.hash = '/login'")
        let rejected = try await web.callAsyncJavaScript(RemoteWorkspaceInput.script, arguments: ["inputID": "relative"], in: nil, in: .page)
        XCTAssertEqual(rejected as? Bool, false)
    }

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
