import Foundation
import SGCore
import SGModels
import SGNetworking
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

    func testKeychainTokenStoreRoundTrip() throws {
        let store = KeychainTokenStore(
            service: "ai.cognition.demo.simplergrants.tests.\(UUID().uuidString)",
            account: "token"
        )
        defer { store.clear() }

        try store.save("first")
        XCTAssertEqual(store.load(), "first")
        try store.save("second")
        XCTAssertEqual(store.load(), "second")
        store.clear()
        XCTAssertNil(store.load())
    }
}
