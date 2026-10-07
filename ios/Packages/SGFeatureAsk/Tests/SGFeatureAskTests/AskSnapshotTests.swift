#if os(iOS)
import SGAsk
import SGCore
import SGDesign
@testable import SGFeatureAsk
import SGModels
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@MainActor
final class AskSnapshotTests: XCTestCase {
    private let snapshotCases = [
        "testAskEmptyComposer",
        "testAskWithText",
        "testAskWithRecents",
        "testAnswer",
        "testAnswerLoading",
        "testAnswerEmpty",
        "testAnswerError",
        "testAnswerXXXL"
    ]

    override func setUp() {
        super.setUp()
        for snapshotCase in snapshotCases {
            let defaults = UserDefaults(suiteName: "AskSnapshotTests.\(snapshotCase)")!
            defaults.removePersistentDomain(forName: "AskSnapshotTests.\(snapshotCase)")
        }
        SGFonts.registerAll()
    }

    func testAskEmptyComposer() async throws {
        let host = try await makeHost(
            AskHomeView(),
            snapshotCase: #function
        )
        assertSnapshot(host, testName: #function)
    }

    func testAskWithText() async throws {
        let host = try await makeHost(
            AskHomeView(initialText: "We run a rural clinic"),
            snapshotCase: #function
        )
        assertSnapshot(host, testName: #function)
    }

    func testAskWithRecents() async throws {
        let host = try await makeHost(
            AskHomeView(),
            snapshotCase: #function,
            recentQuestions: [
                "rural health funding",
                "HRSA-27-014",
                "behavioral health workforce"
            ]
        )
        assertSnapshot(host, testName: #function)
    }

    func testAnswer() async throws {
        let question = "We run a rural clinic and want to expand addiction treatment"
        let answer = try await AskPreviewEngine(mode: .answer).answer(question, removing: [])
        let host = try await makeHost(
            AnswerView(question: question, preloaded: .answer(answer)),
            snapshotCase: #function,
            mode: .answer
        )
        assertSnapshot(host, testName: #function)
    }

    func testAnswerLoading() async throws {
        let host = try await makeHost(
            AnswerView(question: "We run a rural clinic"),
            snapshotCase: #function,
            mode: .loading
        )
        assertSnapshot(host, testName: #function)
    }

    func testAnswerEmpty() async throws {
        let question = "A question with no matching listings"
        let answer = try await AskPreviewEngine(mode: .empty).answer(question, removing: [])
        let host = try await makeHost(
            AnswerView(question: question, preloaded: .answer(answer)),
            snapshotCase: #function,
            mode: .empty
        )
        assertSnapshot(host, testName: #function)
    }

    func testAnswerError() async throws {
        let host = try await makeHost(
            AnswerView(question: "A question that cannot load", preloaded: .failed),
            snapshotCase: #function,
            mode: .failure
        )
        assertSnapshot(host, testName: #function)
    }

    func testAnswerXXXL() async throws {
        let question = "Rural clinic?"
        let answer = try await AskPreviewEngine(mode: .answer).answer(question, removing: [])
        let host = try await makeHost(
            AnswerView(question: question, preloaded: .answer(answer)),
            snapshotCase: #function,
            mode: .answer,
            accessibilitySize: true
        )
        assertSnapshot(host, testName: #function, accessibilitySize: true)
    }

    private func makeHost<Content: View>(
        _ content: Content,
        snapshotCase: String,
        mode: AskPreviewEngine.Mode = .answer,
        recentQuestions: [String] = [],
        accessibilitySize: Bool = false
    ) async throws -> UIViewController {
        let snapshotCase = snapshotCase.replacingOccurrences(of: "()", with: "")
        let defaultsName = "AskSnapshotTests.\(snapshotCase)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        if !recentQuestions.isEmpty {
            let data = try JSONEncoder().encode(recentQuestions)
            defaults.set(String(decoding: data, as: UTF8.self), forKey: "sg.ask.recentQuestions")
        }

        let store = SessionStore(authenticator: PreviewAuthenticator())
        await store.signIn(pivRequired: false)

        var root = AnyView(
            NavigationStack {
                content
            }
            .environment(AppRouter())
            .environment(store)
            .environment(\.grantsDataSource, PreviewDataSource())
            .environment(\.askEngine, AskPreviewEngine(mode: mode))
            .defaultAppStorage(defaults)
        )
        if accessibilitySize {
            root = AnyView(root.environment(\.dynamicTypeSize, .accessibility5))
        }
        let host = UIHostingController(rootView: root)
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        return host
    }

    private func assertSnapshot(
        _ host: UIViewController,
        testName: String,
        accessibilitySize: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let testName = testName.replacingOccurrences(of: "()", with: "")
        let baseImage = Snapshotting<UIViewController, UIImage>.image(
            precision: 0.99,
            perceptualPrecision: 0.98,
            size: CGSize(width: 390, height: 844),
            traits: accessibilitySize
                ? UITraitCollection(
                    preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
                )
                : UITraitCollection()
        )
        let image = Snapshotting<UIViewController, UIImage>.wait(
            for: 1.0,
            on: baseImage
        )
        withSnapshotTesting(record: .never) {
            SnapshotTesting.assertSnapshot(
                matching: host,
                as: image,
                named: testName,
                file: file,
                testName: testName,
                line: line
            )
        }
    }
}
#endif
