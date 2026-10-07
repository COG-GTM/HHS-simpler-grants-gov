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

    func testFormClean() async throws {
        let viewModel = try await realFormViewModel()
        let model = try XCTUnwrap(viewModel.model)
        let step = try XCTUnwrap(viewModel.currentFormStep)
        viewModel.values = validValues(for: step, model: model, startingWith: viewModel.values)
        _ = await viewModel.flushDraft()
        assertApplySnapshot(FormScreenView(viewModel: viewModel), named: "10_form_clean")
    }

    func testFormEmailError() async throws {
        let viewModel = try await realFormViewModel()
        let model = try XCTUnwrap(viewModel.model)
        let step = try XCTUnwrap(viewModel.currentFormStep)
        viewModel.values = validValues(for: step, model: model, startingWith: viewModel.values)
        viewModel.values.setValue(.string("dana@bluefieldchc"), at: FieldPath(keys: ["email"]))
        _ = await viewModel.flushDraft()
        let outcome = await viewModel.continueTapped()
        XCTAssertEqual(outcome, .stayed)
        XCTAssertTrue(viewModel.errors.contains {
            $0.path == "$.email"
                && $0.message == "Enter a valid email address, like name@organization.org"
        })
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
            named: "09_workspace_in_progress_xxxl",
            size: CGSize(width: 390, height: 2400)
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

    private func realFormViewModel() async throws -> FormScreenViewModel {
        let viewModel = FormScreenViewModel(
            applicationId: "apply-demo",
            formId: "sf424",
            dataSource: ApplyReferenceDataSource(
                scenario: .inProgress,
                sf424Definition: try FormPreviewSamples.sf424Definition()
            ),
            progressStore: InMemoryFormProgressStore(
                completedSections: ["apply-demo/sf424": ["step-1"]]
            )
        )
        await viewModel.load()
        return viewModel
    }

    private func validValues(
        for step: FormStep,
        model: FormModel,
        startingWith initialValues: JSONValue
    ) -> JSONValue {
        let fields = step.sections.flatMap(\.fields)
        var values = initialValues
        for _ in 0...fields.count {
            for field in fields {
                guard field.isEditable,
                      FormValidator.isRequired(field, in: values, model: model),
                      !hasNonBlankValue(values.value(at: field.dataPath)) else {
                    continue
                }
                values.setValue(sampleValue(for: field), at: field.dataPath)
            }
        }

        for field in fields where field.isEditable {
            switch field.path {
            case "/properties/email":
                values.setValue(.string("dana@bluefieldchc.org"), at: field.dataPath)
            case "/properties/phone_number":
                values.setValue(.string("(304) 555-0142"), at: field.dataPath)
            case "/properties/applicant_type_code":
                if let option = field.options.first {
                    let value: JSONValue = field.kind == .multiSelect
                        ? .array([option.value])
                        : option.value
                    values.setValue(value, at: field.dataPath)
                }
            default:
                break
            }
        }
        return values
    }

    private func sampleValue(for field: FormField) -> JSONValue {
        if field.kind == .checkbox { return .bool(true) }
        if let option = field.options.first {
            return field.kind == .multiSelect ? .array([option.value]) : option.value
        }
        if field.textFormat == .date { return .string("2026-10-30") }
        if [.integer, .number, .currency].contains(field.textFormat) {
            return .number(1)
        }
        if field.kind == .fieldList { return .array([.object([:])]) }

        let title = field.title.lowercased()
        if title.contains("email") { return .string("dana@bluefieldchc.org") }
        if title.contains("phone") || title.contains("telephone") {
            return .string("(304) 555-0142")
        }
        if title.contains("zip") { return .string("22201") }
        if title.contains("ein") { return .string("12-3456789") }
        if title.contains("state") { return .string("VA") }
        if title.contains("city") { return .string("Arlington") }
        if title.contains("street") { return .string("123 Main Street") }
        return .string("Sample value")
    }

    private func hasNonBlankValue(_ value: JSONValue?) -> Bool {
        guard let value else { return false }
        switch value {
        case .null:
            return false
        case let .string(string):
            return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .array(values):
            return !values.isEmpty
        case let .object(values):
            return !values.isEmpty
        case .bool, .number:
            return true
        }
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
        size: CGSize? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let now = fixedNow
        let size = size ?? snapshotSize
        let root = ApplySnapshotHost {
            view
                .frame(width: size.width, height: size.height)
                .environment(\.timeZone, timeZone)
                .environment(\.applyNow, { now })
        }
        assertSnapshot(
            matching: root,
            as: .image(layout: .fixed(width: size.width, height: size.height)),
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
