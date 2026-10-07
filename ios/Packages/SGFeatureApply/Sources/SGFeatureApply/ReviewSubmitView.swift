import SGCore
import SGDesign
import SGModels
import SwiftUI

public struct ReviewSubmitView: View {
    private let applicationId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.grantsDataSource) private var dataSource
    @Environment(\.applyDraftStore) private var draftStore
    @Environment(\.applyProgressStore) private var progressStore
    @Environment(\.applySubmissionAuthorizer) private var authorizer
    @Environment(AppRouter.self) private var router
    @State private var viewModel: ReviewSubmitViewModel?
    @State private var hasAppeared = false

    public init(applicationId: String) {
        self.applicationId = applicationId
    }

    public init(viewModel: ReviewSubmitViewModel) {
        applicationId = viewModel.applicationId
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            SGNavBar(
                backLabel: "apply.review.back".localized(bundle: .module),
                title: "",
                onBack: nil
            )
            .padding(.horizontal, 12)

            if let viewModel {
                switch viewModel.phase {
                case .loaded:
                    reviewContent(viewModel)
                case .failed(let message):
                    InlineErrorBanner(message: message) {
                        Task { await viewModel.load() }
                    }
                    .padding(20)
                    Spacer()
                case .loading, .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ApplyTheme.C.canvas)
        .applyDataSourceEnvironment(dataSource)
        .toolbarHiddenForApply(hideTabBar: true)
        .task {
            guard let viewModel else {
                let vm = ReviewSubmitViewModel(
                    applicationId: applicationId,
                    dataSource: ApplyDebugContext.dataSource(default: dataSource),
                    draftStore: draftStore,
                    progressStore: ApplyDebugContext.progressStore(default: progressStore),
                    authorizer: authorizer
                )
                self.viewModel = vm
                await vm.load()
                return
            }
            if case .loading = viewModel.phase {
                await viewModel.load()
            }
        }
        .onAppear {
            if hasAppeared {
                Task { await viewModel?.load() }
            }
            hasAppeared = true
        }
        .confirmationDialog(
            "apply.review.confirm_title".localized(bundle: .module),
            isPresented: Binding(
                get: { viewModel?.showConfirmation ?? false },
                set: { viewModel?.showConfirmation = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("apply.review.submit".localized(bundle: .module)) {
                Task { await performSubmission(viewModel) }
            }
            .accessibilityIdentifier("apply.review.confirm.submit")
            Button("apply.review.cancel".localized(bundle: .module), role: .cancel) {}
        } message: {
            Text("apply.review.confirm_message".localized(bundle: .module))
        }
    }

    @ViewBuilder
    private func reviewContent(_ viewModel: ReviewSubmitViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("apply.review.title".localized(bundle: .module))
                        .font(ApplyTheme.F.serif(30))
                        .foregroundStyle(ApplyTheme.C.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(contextLine(viewModel))
                        .font(ApplyTheme.F.sans(15))
                        .foregroundStyle(ApplyTheme.C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    VStack(spacing: 0) {
                        ForEach(Array((viewModel.requiredRows + viewModel.optionalRows).enumerated()), id: \.element.id) { index, row in
                            reviewRow(row)
                            if index < viewModel.requiredRows.count + viewModel.optionalRows.count - 1 {
                                Rectangle()
                                    .fill(ApplyTheme.C.lineSoft)
                                    .frame(height: 1)
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: ApplyTheme.R.card, style: .continuous))
                    .applyCard()
                    .padding(.top, 20)

                    if viewModel.incompleteRequiredCount > 0 {
                        Text(
                            String.localizedStringWithFormat(
                                "apply.review.incomplete".localized(bundle: .module),
                                viewModel.incompleteRequiredCount
                            )
                        )
                        .font(ApplyTheme.F.sans(14))
                        .foregroundStyle(ApplyTheme.C.soonFg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(ApplyTheme.C.soonBg, in: RoundedRectangle(cornerRadius: ApplyTheme.R.row))
                        .padding(.top, 14)
                        .accessibilityElement(children: .combine)
                    }

                    if !viewModel.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                "apply.review.warnings_title".localized(bundle: .module),
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(ApplyTheme.F.sans(16, .semibold))
                            .foregroundStyle(ApplyTheme.C.ink)
                            .accessibilityAddTraits(.isHeader)
                            ForEach(viewModel.warnings) { warning in
                                Text(
                                    String(
                                        format: "apply.review.warning".localized(bundle: .module),
                                        warning.formName,
                                        warning.message
                                    )
                                )
                                .font(ApplyTheme.F.sans(13))
                                .foregroundStyle(ApplyTheme.C.muted)
                            }
                        }
                        .padding(.top, 20)
                    }

                    if let message = viewModel.bannerMessage {
                        InlineErrorBanner(message: message) {
                            Task { await performSubmission(viewModel) }
                        }
                        .padding(.top, 16)
                    }

                    certificationCard(viewModel)
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, ApplyTheme.S.margin)
                .padding(.top, 8)
            }
            submitFooter(viewModel)
        }
    }

    private func reviewRow(_ row: ApplyFormRow) -> some View {
        HStack(spacing: 10) {
            ApplyStatusMark(state: row.state, size: 20)
            Text(row.displayName)
                .font(ApplyTheme.F.sans(14))
                .foregroundStyle(ApplyTheme.C.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(shortState(row.state))
                .font(ApplyTheme.F.sans(13))
                .foregroundStyle(stateColor(row.state))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                router.push(.form(applicationId: applicationId, formId: row.id))
            } label: {
                Text("apply.review.edit".localized(bundle: .module))
                    .font(ApplyTheme.F.sans(13, .semibold))
                    .foregroundStyle(ApplyTheme.C.navy)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                String(format: "apply.review.edit_accessibility".localized(bundle: .module), row.shortName)
            )
            .accessibilityIdentifier("apply.review.edit.\(row.id)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: 44)
    }

    private func certificationCard(_ viewModel: ReviewSubmitViewModel) -> some View {
        Button {
            viewModel.certified.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(viewModel.certified ? ApplyTheme.C.navy : .white)
                    .frame(width: 22, height: 22)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(viewModel.certified ? ApplyTheme.C.navy : ApplyTheme.C.subtle, lineWidth: 2)
                        if viewModel.certified {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .accessibilityHidden(true)
                Text("apply.review.certification".localized(bundle: .module))
                    .font(ApplyTheme.F.sans(14))
                    .foregroundStyle(ApplyTheme.C.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .applyCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("apply.review.certification".localized(bundle: .module))
        .accessibilityValue(
            (viewModel.certified ? "apply.review.checked" : "apply.review.not_checked")
                .localized(bundle: .module)
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("apply.review.certify")
    }

    private func submitFooter(_ viewModel: ReviewSubmitViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("apply.review.demo_note".localized(bundle: .module))
                .font(ApplyTheme.F.sans(12))
                .foregroundStyle(ApplyTheme.C.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("apply.review.demo_note")

            Button {
                Task {
                    let step = await viewModel.requestSubmit()
                    if case let .submitted(result) = step, let result {
                        router.push(
                            .submitted(
                                applicationId: applicationId,
                                trackingNumber: result.trackingNumber
                            )
                        )
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white)
                    }
                    Text(
                        viewModel.isSubmitting
                            ? "apply.review.submitting".localized(bundle: .module)
                            : "apply.review.submit".localized(bundle: .module)
                    )
                }
            }
            .buttonStyle(ApplyPrimaryButtonStyle(isEnabled: viewModel.canSubmit))
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("apply.review.submit")
        }
        .padding(.horizontal, ApplyTheme.S.margin)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ApplyTheme.C.canvas)
        .overlay(alignment: .top) {
            Rectangle().fill(ApplyTheme.C.line).frame(height: 1)
        }
    }

    private func performSubmission(_ viewModel: ReviewSubmitViewModel?) async {
        guard let viewModel, let result = await viewModel.performSubmit() else { return }
        router.push(.submitted(applicationId: applicationId, trackingNumber: result.trackingNumber))
    }

    private func contextLine(_ viewModel: ReviewSubmitViewModel) -> String {
        if let agencyName = viewModel.agencyName {
            return String(
                format: "apply.review.context".localized(bundle: .module),
                agencyName,
                viewModel.organizationName
            )
        }
        return String(
            format: "apply.review.context_no_agency".localized(bundle: .module),
            viewModel.organizationName
        )
    }

    private func shortState(_ state: ApplyFormState) -> String {
        switch state {
        case .complete:
            return "apply.workspace.state_complete".localized(bundle: .module)
        case .inProgress:
            return "apply.workspace.short_in_progress".localized(bundle: .module)
        case .notStarted:
            return "apply.workspace.state_not_started".localized(bundle: .module)
        }
    }

    private func stateColor(_ state: ApplyFormState) -> Color {
        switch state {
        case .complete: return ApplyTheme.C.green
        case .inProgress: return ApplyTheme.C.navy
        case .notStarted: return ApplyTheme.C.subtle
        }
    }
}
