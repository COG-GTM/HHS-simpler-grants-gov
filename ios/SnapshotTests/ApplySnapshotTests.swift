import SGDesign
@_spi(Snapshots) import SGFeatureApply
import SGForms
import SGModels
import SnapshotTesting
import SwiftUI
import XCTest

@MainActor
final class ApplySnapshotTests: XCTestCase {
    private let snapshotSize = CGSize(width: 390, height: 844)
    private let timeZone = TimeZone(identifier: "America/New_York")!

    override func setUp() {
        super.setUp()
        SGFonts.registerAll()
    }

    override func tearDown() {
        isRecording = false
        super.tearDown()
    }

    func testWorkspaceInProgress() async {
        let viewModel = await workspaceViewModel(scenario: .inProgress)
        assertApplySnapshot(
            ApplicationWorkspaceView(viewModel: viewModel),
            named: "09_workspace_in_progress"
        )
    }

    func testWorkspaceAllComplete() async {
        let viewModel = await workspaceViewModel(scenario: .allComplete)
        assertApplySnapshot(
            ApplicationWorkspaceView(viewModel: viewModel),
            named: "09_workspace_all_complete"
        )
    }

    func testHomeEmpty() async {
        let now = fixedNow
        let viewModel = WorkspaceViewModel(
            applicationId: nil,
            dataSource: ApplyReferenceDataSource(scenario: .empty),
            progressStore: ApplyReferenceDataSource.progressStore(for: .empty),
            now: { now },
            timeZone: timeZone
        )
        await viewModel.load()
        assertApplySnapshot(ApplyHomeView(viewModel: viewModel), named: "09_home_empty")
    }

    func testFormClean() async {
        let viewModel = await formViewModel(progressStore: InMemoryFormProgressStore())
        assertApplySnapshot(FormScreenView(viewModel: viewModel), named: "10_form_clean")
    }

    func testFormEmailError() async {
        let error = FieldError(
            path: "/properties/email",
            message: "Enter a valid email address, like name@organization.org"
        )
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(scenario: .inProgress),
            progressStore: InMemoryFormProgressStore(),
            validator: { _, _, _ in [error] }
        )
        await viewModel.load()
        _ = await viewModel.continueTapped()
        assertApplySnapshot(FormScreenView(viewModel: viewModel), named: "10_form_email_error")
    }

    func testReview() async {
        let viewModel = await reviewViewModel(scenario: .allComplete)
        assertApplySnapshot(ReviewSubmitView(viewModel: viewModel), named: "11_review")
    }

    func testReviewReady() async {
        let viewModel = await reviewViewModel(scenario: .allComplete)
        viewModel.certified = true
        assertApplySnapshot(ReviewSubmitView(viewModel: viewModel), named: "11_review_ready")
    }

    func testSubmitted() async {
        let now = fixedNow
        let viewModel = SubmittedViewModel(
            applicationId: "apply-demo",
            trackingNumber: "GRANT14102837",
            dataSource: ApplyReferenceDataSource(scenario: .inProgress),
            now: { now }
        )
        await viewModel.load()
        assertApplySnapshot(SubmittedView(viewModel: viewModel), named: "12_submitted")
    }

    func testWorkspaceInProgressXXXL() async {
        let viewModel = await workspaceViewModel(scenario: .inProgress)
        assertApplySnapshot(
            ApplicationWorkspaceView(viewModel: viewModel)
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge),
            named: "09_workspace_in_progress_xxxl"
        )
    }

    private func workspaceViewModel(
        scenario: ApplyReferenceDataSource.Scenario
    ) async -> WorkspaceViewModel {
        let now = fixedNow
        let viewModel = WorkspaceViewModel(
            applicationId: "apply-demo",
            dataSource: ApplyReferenceDataSource(scenario: scenario),
            progressStore: ApplyReferenceDataSource.progressStore(for: scenario),
            now: { now },
            timeZone: timeZone
        )
        await viewModel.load()
        return viewModel
    }

    private func formViewModel(
        progressStore: any FormProgressStore
    ) async -> FormScreenViewModel {
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(scenario: .inProgress),
            progressStore: progressStore
        )
        await viewModel.load()
        return viewModel
    }

    private func reviewViewModel(
        scenario: ApplyReferenceDataSource.Scenario
    ) async -> ReviewSubmitViewModel {
        let viewModel = ReviewSubmitViewModel(
            applicationId: "apply-demo",
            dataSource: ApplyReferenceDataSource(scenario: scenario),
            progressStore: ApplyReferenceDataSource.progressStore(for: scenario),
            authorizer: SnapshotAuthorizer()
        )
        await viewModel.load()
        return viewModel
    }

    private func assertApplySnapshot<V: View>(
        _ view: V,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let now = fixedNow
        let root = ApplySnapshotHost {
            view
                .frame(width: snapshotSize.width, height: snapshotSize.height)
                .environment(\.timeZone, timeZone)
                .environment(\.applyNow, { now })
        }
        assertSnapshot(
            matching: root,
            as: .image(layout: .fixed(width: snapshotSize.width, height: snapshotSize.height)),
            named: name,
            file: file,
            testName: testName,
            line: line
        )
    }

    private var fixedNow: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 9, minute: 41))!
    }
}

private struct SnapshotAuthorizer: SubmissionAuthorizing {
    func authorize(reason: String) async -> SubmissionAuthorization { .unavailable }
}
