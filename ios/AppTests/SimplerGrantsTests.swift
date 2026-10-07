import SGCore
import SGModels
import XCTest

final class SimplerGrantsTests: XCTestCase {
    func testDataModeDefaultsToSample() {
        XCTAssertEqual(AppEnvironment(arguments: []).dataMode, .sample)
    }

    func testRemoteLiveBaseURLFallsBackToLoopback() {
        let environment = AppEnvironment(arguments: [
            "-SGDataMode", "live",
            "-SGAPIBaseURL", "https://example.com"
        ])
        guard case let .live(baseURL) = environment.dataMode else {
            return XCTFail("Expected live mode")
        }
        XCTAssertEqual(baseURL.absoluteString, "http://127.0.0.1:8080")
    }

    @MainActor
    func testSessionStoreCanContinueAsGuest() {
        let sessionStore = SessionStore(authenticator: PreviewAuthenticator())
        sessionStore.continueAsGuest()
        XCTAssertEqual(sessionStore.state, .guest)
    }
}
