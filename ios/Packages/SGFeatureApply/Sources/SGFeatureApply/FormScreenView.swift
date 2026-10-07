import SGCore
import SGDesign
import SGForms
import SGModels
import SwiftUI

public struct FormScreenView: View {
    private let applicationId: String
    private let formId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.grantsDataSource) private var dataSource
    @Environment(\.applyDraftStore) private var draftStore
    @Environment(\.applyProgressStore) private var progressStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: FormScreenViewModel?
    @AccessibilityFocusState private var errorSummaryFocused: Bool

    public init(applicationId: String, formId: String) {
        self.applicationId = applicationId
        self.formId = formId
    }

    public init(viewModel: FormScreenViewModel) {
        applicationId = viewModel.applicationId
        formId = viewModel.formId
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            if let viewModel {
                SGNavBar(
                    backLabel: "apply.form.back".localized(bundle: .module),
                    title: viewModel.shortName,
                    onBack: {
                        Task {
                            await viewModel.backTapped()
                            dismiss()
                        }
                    }
                )
                .padding(.horizontal, 12)
                .overlay(alignment: .trailing) {
                    if viewModel.stepCount > 0 {
                        Text(
                            String(
                                format: "apply.form.step_count".localized(bundle: .module),
                                min(viewModel.currentStep + 1, viewModel.stepCount),
                                viewModel.stepCount
                            )
                        )
                        .font(ApplyTheme.F.sans(13))
                        .foregroundStyle(ApplyTheme.C.subtle)
                        .frame(width: 54, height: 44, alignment: .trailing)
                        .padding(.trailing, 12)
                        .accessibilityLabel(
                            String(
                                format: "apply.form.step_accessibility".localized(bundle: .module),
                                min(viewModel.currentStep + 1, viewModel.stepCount),
                                viewModel.stepCount
                            )
                        )
                        .accessibilityIdentifier("apply.form.step")
                    }
                }

                if viewModel.stepCount > 0 {
                    stepProgress(viewModel)
                }
                switch viewModel.phase {
                case .loaded:
                    formContent(viewModel)
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
                let vm = FormScreenViewModel(
                    applicationId: applicationId,
                    formId: formId,
                    dataSource: ApplyDebugContext.dataSource(default: dataSource),
                    draftStore: draftStore,
                    progressStore: ApplyDebugContext.progressStore(default: progressStore)
                )
                self.viewModel = vm
                await vm.load()
                return
            }
            if case .loading = viewModel.phase {
                await viewModel.load()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await viewModel?.sceneDidBackground() }
            }
        }
        .onChange(of: viewModel?.focusToken) { _, _ in
            guard let viewModel, let firstError = viewModel.errors.first else { return }
            errorSummaryFocused = true
            withAnimation {
                errorScrollProxy?.scrollTo(firstError.path, anchor: .top)
            }
        }
    }

    @State private var errorScrollProxy: ScrollViewProxy?

    @ViewBuilder
    private func formContent(_ viewModel: FormScreenViewModel) -> some View {
        if let step = viewModel.currentFormStep {
            let values = Binding(
                get: { viewModel.values },
                set: { viewModel.values = $0 }
            )
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(viewModel.formDisplayName)
                                .font(ApplyTheme.F.sans(13))
                                .foregroundStyle(ApplyTheme.C.muted)
                            Text(step.title)
                                .font(ApplyTheme.F.serif(26))
                                .foregroundStyle(ApplyTheme.C.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.top, 6)

                            if let description = step.sections.first?.description, !description.isEmpty {
                                Text(description)
                                    .font(ApplyTheme.F.sans(14))
                                    .foregroundStyle(ApplyTheme.C.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 8)
                            }

                            if step.sections.flatMap(\.fields).contains(where: {
                                viewModel.prefilledPaths.contains($0.path)
                            }) {
                                Text("apply.form.prefill_helper".localized(bundle: .module))
                                    .font(ApplyTheme.F.sans(14))
                                    .foregroundStyle(ApplyTheme.C.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 8)
                            }

                            if !viewModel.errors.isEmpty {
                                errorSummary(viewModel.errors)
                                    .id("apply.form.error_summary")
                                    .accessibilityFocused($errorSummaryFocused)
                                    .padding(.top, 16)
                            }

                            if let message = viewModel.bannerMessage {
                                InlineErrorBanner(message: message) {
                                    Task { await viewModel.retry() }
                                }
                                .padding(.top, 16)
                            }

                            VStack(alignment: .leading, spacing: 24) {
                                ForEach(step.sections) { section in
                                    let sectionErrors = viewModel.firstErrorSectionID == section.id
                                        ? viewModel.sectionErrors[section.id] ?? []
                                        : []
                                    FormSectionView(
                                        section: section,
                                        values: values,
                                        errors: sectionErrors,
                                        prefill: viewModel.prefill,
                                        showsTitle: step.sections.count > 1
                                    )
                                }
                            }
                            .padding(.top, 12)
                        }
                        .padding(.horizontal, ApplyTheme.S.margin)
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                    }
                    .onAppear {
                        errorScrollProxy = proxy
                    }
                    .onChange(of: viewModel.focusToken) { _, _ in
                        if let path = viewModel.errors.first?.path {
                            proxy.scrollTo(path, anchor: .top)
                            proxy.scrollTo("apply.form.error_summary", anchor: .top)
                        }
                    }
                }
                saveStatusLine(viewModel)
                footer(viewModel)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func stepProgress(_ viewModel: FormScreenViewModel) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<viewModel.stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= viewModel.currentStep ? ApplyTheme.C.navy : ApplyTheme.C.line)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, ApplyTheme.S.margin)
        .accessibilityElement()
        .accessibilityLabel("apply.form.progress".localized(bundle: .module))
        .accessibilityValue(
            String(
                format: "apply.form.step_accessibility".localized(bundle: .module),
                viewModel.currentStep + 1,
                viewModel.stepCount
            )
        )
    }

    private func errorSummary(_ errors: [FieldError]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(validationSummaryMessage(fieldCount: errors.count))
                .font(ApplyTheme.F.sans(14, .semibold))
                .foregroundStyle(ApplyTheme.C.soonFg)
            ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                Text(error.message)
                    .font(ApplyTheme.F.sans(13))
                    .foregroundStyle(ApplyTheme.C.red)
                    .id(error.path)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ApplyTheme.C.soonBg, in: RoundedRectangle(cornerRadius: ApplyTheme.R.row))
        .accessibilityElement(children: .contain)
    }

    private func saveStatusLine(_ viewModel: FormScreenViewModel) -> some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon(viewModel.saveStatus))
                .accessibilityHidden(true)
            Text(statusText(viewModel.saveStatus))
        }
        .font(ApplyTheme.F.sans(13))
        .foregroundStyle(ApplyTheme.C.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ApplyTheme.S.margin)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("apply.form.save_status")
    }

    private func statusIcon(_ status: FormSaveStatus) -> String {
        switch status {
        case .idle: return "icloud"
        case .saving: return "arrow.triangle.2.circlepath"
        case .saved: return "checkmark.circle"
        case .offline: return "iphone"
        case .failed: return "exclamationmark.icloud"
        }
    }

    private func statusText(_ status: FormSaveStatus) -> String {
        switch status {
        case .idle: return "apply.form.save_idle".localized(bundle: .module)
        case .saving: return "apply.form.save_saving".localized(bundle: .module)
        case .saved: return "apply.form.save_saved".localized(bundle: .module)
        case .offline: return "apply.form.save_offline".localized(bundle: .module)
        case .failed: return "apply.form.save_failed".localized(bundle: .module)
        }
    }

    private func footer(_ viewModel: FormScreenViewModel) -> some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    if await viewModel.saveDraftTapped() {
                        dismiss()
                    }
                }
            } label: {
                Text("apply.form.save_draft".localized(bundle: .module))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 16)
            }
            .buttonStyle(SecondaryButton())
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 52)
            .accessibilityIdentifier("apply.form.save_draft")

            Button {
                Task {
                    let outcome = await viewModel.continueTapped()
                    if outcome == .finished {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSyncing {
                        ProgressView().tint(.white)
                    }
                    Text("apply.form.continue".localized(bundle: .module))
                }
            }
            .buttonStyle(ApplyPrimaryButtonStyle(isEnabled: !viewModel.isSyncing))
            .frame(maxWidth: .infinity)
            .disabled(viewModel.isSyncing)
            .accessibilityIdentifier("apply.form.continue")
        }
        .padding(.horizontal, ApplyTheme.S.margin)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(ApplyTheme.C.canvas)
        .overlay(alignment: .top) {
            Rectangle().fill(ApplyTheme.C.line).frame(height: 1)
        }
    }
}

func validationSummaryMessage(fieldCount: Int) -> String {
    String.localizedStringWithFormat(
        "apply.form.validation_summary".localized(bundle: .module),
        fieldCount
    )
}
