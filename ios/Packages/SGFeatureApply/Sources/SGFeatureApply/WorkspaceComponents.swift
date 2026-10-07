import SGCore
import SGDesign
import SGModels
import SwiftUI

struct WorkspaceContent: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.timeZone) private var timeZone
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var opportunityNumberFontSize: CGFloat = 12

    let viewModel: WorkspaceViewModel
    let applicationId: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryCard
                sectionHeading("apply.workspace.required_forms", trailing: "apply.workspace.saved_automatically")
                    .padding(.top, 26)
                    .padding(.bottom, 10)
                formList(viewModel.requiredRows)
                if !viewModel.optionalRows.isEmpty {
                    sectionHeading("apply.workspace.optional_forms")
                        .padding(.top, 24)
                        .padding(.bottom, 10)
                    formList(viewModel.optionalRows)
                }

                Button {
                    router.push(.review(applicationId: applicationId))
                } label: {
                    Text("apply.workspace.review".localized(bundle: .module))
                }
                .buttonStyle(ApplyPrimaryButtonStyle(isEnabled: viewModel.canReview))
                .disabled(!viewModel.canReview)
                .accessibilityIdentifier("apply.workspace.review")
                .padding(.top, 20)

                if !viewModel.canReview {
                    Text("apply.workspace.complete_required".localized(bundle: .module))
                        .font(ApplyTheme.F.sans(13))
                        .foregroundStyle(ApplyTheme.C.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                Text("apply.workspace.authorized_representative".localized(bundle: .module))
                    .font(ApplyTheme.F.sans(13))
                    .foregroundStyle(ApplyTheme.C.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                if viewModel.allApplications.count > 1 {
                    applicationList(viewModel.allApplications)
                }
            }
            .padding(.horizontal, ApplyTheme.S.margin)
            .padding(.top, 8)
        }
        .background(ApplyTheme.C.canvas)
    }

    private func applicationList(_ applications: [ApplicationSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("apply.home.your_applications".localized(bundle: .module))
                .font(ApplyTheme.F.sans(20, .semibold))
                .foregroundStyle(ApplyTheme.C.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(applications) { application in
                Button {
                    router.push(.application(id: application.applicationId))
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(application.applicationName ?? application.competition.competitionTitle ?? "")
                                .font(ApplyTheme.F.sans(15, .semibold))
                                .foregroundStyle(ApplyTheme.C.ink)
                                .multilineTextAlignment(.leading)
                            StatusChip(status: applicationStatus(application.applicationStatus))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(ApplyTheme.C.subtle)
                            .accessibilityHidden(true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .applyCard()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 24)
    }

    private func applicationStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "in_progress":
            return "apply.status.in_progress".localized(bundle: .module)
        case "complete":
            return "apply.status.complete".localized(bundle: .module)
        default:
            return status
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let opportunityNumber = viewModel.opportunityNumber {
                Text(opportunityNumber)
                    .font(.system(size: opportunityNumberFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(ApplyTheme.C.subtle)
            }
            Text(viewModel.opportunityTitle)
                .font(ApplyTheme.F.serif(19))
                .foregroundStyle(ApplyTheme.C.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, viewModel.opportunityNumber == nil ? 0 : 6)
            Text(
                String(
                    format: "apply.workspace.applying_as".localized(bundle: .module),
                    viewModel.organizationName
                )
            )
            .font(ApplyTheme.F.sans(14))
            .foregroundStyle(ApplyTheme.C.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(ApplyTheme.C.lineSoft)
                    Capsule()
                        .fill(ApplyTheme.C.green)
                        .frame(width: geometry.size.width * viewModel.progressFraction)
                }
            }
            .frame(height: 6)
            .padding(.top, 14)
            .accessibilityElement()
            .accessibilityLabel("apply.workspace.progress".localized(bundle: .module))
            .accessibilityValue(
                String(
                    format: "apply.workspace.progress_percent".localized(bundle: .module),
                    Int(viewModel.progressFraction * 100)
                )
            )

            progressAndDueRow
                .padding(.top, 8)
        }
        .padding(16)
        .applyCard()
    }

    @ViewBuilder
    private var progressAndDueRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                completedFormsLabel
                if let dueDate = viewModel.dueDate, let days = viewModel.daysRemaining {
                    dueDateLabel(date: dueDate, days: days)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                completedFormsLabel
                Spacer(minLength: 0)
                if let dueDate = viewModel.dueDate, let days = viewModel.daysRemaining {
                    dueDateLabel(date: dueDate, days: days)
                }
            }
        }
    }

    private var completedFormsLabel: some View {
        Text(workspaceFormsCompleteText(
            completedCount: viewModel.completedRequiredCount,
            requiredCount: viewModel.requiredCount
        ))
        .font(ApplyTheme.F.sans(13, .semibold))
        .foregroundStyle(ApplyTheme.C.ink)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func dueDateLabel(date: Date, days: Int) -> some View {
        Text(workspaceDueLabel(date: date, days: days, timeZone: timeZone))
            .font(ApplyTheme.F.sans(13, .semibold))
            .foregroundStyle(viewModel.isDueSoon ? ApplyTheme.C.red : ApplyTheme.C.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(workspaceDueLabel(date: date, days: days, timeZone: timeZone))
    }

    @ViewBuilder
    private func sectionHeading(_ titleKey: String, trailing: String? = nil) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(titleKey.localized(bundle: .module))
                    .font(ApplyTheme.F.sans(20, .semibold))
                    .foregroundStyle(ApplyTheme.C.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let trailing {
                    Text(trailing.localized(bundle: .module))
                        .font(ApplyTheme.F.sans(13))
                        .foregroundStyle(ApplyTheme.C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(titleKey.localized(bundle: .module))
                    .font(ApplyTheme.F.sans(20, .semibold))
                    .foregroundStyle(ApplyTheme.C.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing.localized(bundle: .module))
                        .font(ApplyTheme.F.sans(13))
                        .foregroundStyle(ApplyTheme.C.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private func formList(_ rows: [ApplyFormRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    router.push(.form(applicationId: applicationId, formId: row.id))
                } label: {
                    WorkspaceFormRow(row: row)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    String(
                        format: "apply.workspace.form_accessibility".localized(bundle: .module),
                        row.displayName,
                        workspaceStateDescription(row.state)
                    )
                )
                .accessibilityHint("apply.workspace.open_form_hint".localized(bundle: .module))
                .accessibilityIdentifier("apply.workspace.form.\(row.id)")
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(ApplyTheme.C.lineSoft)
                        .frame(height: 1)
                        .padding(.leading, 56)
                        .accessibilityHidden(true)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ApplyTheme.R.card, style: .continuous))
        .applyCard()
    }

}

func workspaceFormsCompleteText(completedCount: Int, requiredCount: Int) -> String {
    String.localizedStringWithFormat(
        "apply.workspace.forms_complete".localized(bundle: .module),
        completedCount,
        requiredCount
    )
}

func workspaceDueLabel(date: Date, days: Int, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = timeZone
    formatter.dateFormat = "MMM d"
    let dateString = formatter.string(from: date)
    if days < 0 {
        return String(format: "apply.workspace.past_due".localized(bundle: .module), dateString)
    }
    return String.localizedStringWithFormat(
        "apply.workspace.due_days".localized(bundle: .module),
        dateString,
        days
    )
}

func workspaceStateDescription(_ state: ApplyFormState) -> String {
    switch state {
    case .complete:
        return "apply.workspace.state_complete".localized(bundle: .module)
    case let .inProgress(completed, total):
        guard total > 1 else {
            return "apply.workspace.short_in_progress".localized(bundle: .module)
        }
        return String.localizedStringWithFormat(
            "apply.workspace.state_in_progress".localized(bundle: .module),
            completed,
            total
        )
    case .notStarted:
        return "apply.workspace.state_not_started".localized(bundle: .module)
    }
}

struct WorkspaceFormRow: View {
    let row: ApplyFormRow

    var body: some View {
        HStack(spacing: 12) {
            ApplyStatusMark(state: row.state, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .font(ApplyTheme.F.sans(15, .semibold))
                    .foregroundStyle(ApplyTheme.C.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(stateDescription)
                    .font(ApplyTheme.F.sans(13))
                    .foregroundStyle(stateColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ApplyTheme.C.subtle)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var stateDescription: String {
        workspaceStateDescription(row.state)
    }

    private var stateColor: Color {
        switch row.state {
        case .complete: return ApplyTheme.C.green
        case .inProgress: return ApplyTheme.C.navy
        case .notStarted: return ApplyTheme.C.subtle
        }
    }
}

struct ApplyStatusMark: View {
    let state: ApplyFormState
    var size: CGFloat
    @ScaledMetric(relativeTo: .body) private var scaledMarkSize: CGFloat = 24

    private var renderedSize: CGFloat {
        min(size * scaledMarkSize / 24, size * 2)
    }

    private var renderedStrokeWidth: CGFloat {
        min(2 * scaledMarkSize / 24, 4)
    }

    var body: some View {
        Group {
            switch state {
            case .complete:
                Circle()
                    .fill(ApplyTheme.C.green)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: renderedSize * 0.48, weight: .bold))
                            .foregroundStyle(.white)
                    }
            case .inProgress:
                Circle().stroke(ApplyTheme.C.navy, lineWidth: renderedStrokeWidth)
            case .notStarted:
                Circle().stroke(ApplyTheme.C.control, lineWidth: renderedStrokeWidth)
            }
        }
        .frame(width: renderedSize, height: renderedSize)
        .accessibilityHidden(true)
    }
}
