import SGAsk
import SGCore
import SGDesign
import SGFeatureAsk
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
        assertImage(host, named: #function)
    }

    func testAskWithText() async throws {
        let host = try await makeHost(
            AskHomeView(initialText: "We run a rural clinic"),
            snapshotCase: #function
        )
        assertImage(host, named: #function)
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
        assertImage(host, named: #function)
    }

    func testAnswer() async throws {
        let question = "We run a rural clinic and want to expand addiction treatment"
        let answer = try await AskPreviewEngine(mode: .answer).answer(question, removing: [])
        let host = try await makeHost(
            AnswerView(question: question, preloaded: .answer(answer)),
            snapshotCase: #function,
            mode: .answer
        )
        assertImage(host, named: #function)
    }

    func testAnswerLoading() async throws {
        let host = try await makeHost(
            AnswerView(question: "We run a rural clinic"),
            snapshotCase: #function,
            mode: .loading
        )
        assertImage(host, named: #function)
    }

    func testAnswerEmpty() async throws {
        let question = "A question with no matching listings"
        let answer = try await AskPreviewEngine(mode: .empty).answer(question, removing: [])
        let host = try await makeHost(
            AnswerView(question: question, preloaded: .answer(answer)),
            snapshotCase: #function,
            mode: .empty
        )
        assertImage(host, named: #function)
    }

    func testAnswerError() async throws {
        let host = try await makeHost(
            AnswerView(question: "A question that cannot load", preloaded: .failed),
            snapshotCase: #function,
            mode: .failure
        )
        assertImage(host, named: #function)
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
        assertImage(host, named: #function)
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

    private func assertImage(
        _ host: UIViewController,
        named name: String
    ) {
        let snapshotName = name.replacingOccurrences(of: "()", with: "")
        let size: CGSize
        switch snapshotName {
        case "testAskWithRecents":
            size = CGSize(width: 390, height: 1200)
        case "testAnswer":
            size = CGSize(width: 390, height: 1400)
        default:
            size = CGSize(width: 390, height: 844)
        }
        let accessibilityTraits = snapshotName.contains("XXXL")
            ? UITraitCollection(
                preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
            )
            : UITraitCollection()
        let config = ViewImageConfig(
            safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
            size: size,
            traits: UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .light),
                accessibilityTraits
            ])
        )
        withSnapshotTesting(record: .never) {
            assertSnapshot(
                of: host,
                as: .image(on: config, precision: 0.99, perceptualPrecision: 0.98),
                named: snapshotName
            )
        }
    }
}
