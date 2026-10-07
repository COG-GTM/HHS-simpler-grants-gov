import Foundation
import XCTest
@testable import SGFeatureProfile

@MainActor
final class RoadmapTests: XCTestCase {
    func testBundledRoadmapDecodesWithUniqueIDsAndNoReleasedVoteCounts() throws {
        let content = try RoadmapContent.loadBundled()
        XCTAssertFalse(content.sections.isEmpty)
        XCTAssertTrue(content.sections.allSatisfy { !$0.items.isEmpty })

        let ids = content.sections.flatMap(\.items).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)

        let releasedItems = content.sections.flatMap(\.items).filter { $0.status == .released }
        XCTAssertFalse(releasedItems.isEmpty)
        XCTAssertTrue(releasedItems.allSatisfy { $0.baseVotes == nil })
    }

    func testInvalidStatusFailsToDecode() {
        let data = Data(
            """
            {
              "id": "invalid",
              "status": "under_review",
              "title": "Example",
              "summary": "",
              "baseVotes": 1
            }
            """.utf8
        )
        XCTAssertThrowsError(try JSONDecoder().decode(RoadmapItem.self, from: data))
    }

    func testVotesToggleAndPersistAcrossStoreInstances() {
        let suiteName = "SGFeatureProfileTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let item = RoadmapItem(
            id: "planned-item",
            status: .planned,
            title: "Example",
            summary: "",
            baseVotes: 12
        )

        let firstStore = RoadmapVoteStore(defaults: defaults)
        XCTAssertFalse(firstStore.hasVoted(item.id))
        XCTAssertEqual(firstStore.count(for: item), 12)
        firstStore.toggle(item.id)

        let secondStore = RoadmapVoteStore(defaults: defaults)
        XCTAssertTrue(secondStore.hasVoted(item.id))
        XCTAssertEqual(secondStore.count(for: item), 13)
        secondStore.toggle(item.id)
        XCTAssertEqual(RoadmapVoteStore(defaults: defaults).count(for: item), 12)
    }

    func testReleasedItemsHaveNoVoteCount() {
        let store = RoadmapVoteStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let item = RoadmapItem(
            id: "released-item",
            status: .released,
            title: "Example",
            summary: "",
            baseVotes: nil
        )
        XCTAssertNil(store.count(for: item))
    }

    func testFeedbackMailEncodesSubjectAndBodyAndRejectsEmptyMessage() throws {
        let message = "A line & another?\nMore details"
        let url = try XCTUnwrap(FeedbackMail.url(message: message))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, FeedbackMail.recipient)
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "subject" })?.value,
            "Simpler.Grants.gov demo feedback"
        )
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "body" })?.value,
            message
        )
        XCTAssertNil(FeedbackMail.url(message: " \n\t "))
    }
}
