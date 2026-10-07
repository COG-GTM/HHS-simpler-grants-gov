import SGCore
import SGDesign
import SGModels
import SwiftUI
#if os(iOS)
import UIKit
import SafariServices
#endif

public struct OpportunityDetailView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.grantsDataSource) private var dataSource
    @State private var viewModel: OpportunityDetailViewModel?
    @State private var isSummaryExpanded = false
    @State private var safariItem: SafariItem?

    private let opportunityId: String?

    public init(opportunityId: String) {
        self.opportunityId = opportunityId
        _viewModel = State(initialValue: nil)
    }

    public init(viewModel: OpportunityDetailViewModel) {
        opportunityId = nil
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        Group {
            if let viewModel {
                detailContent(viewModel)
            } else {
                VStack(spacing: 0) {
                    DemoBanner()
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(SearchTheme.C.canvas)
            }
        }
        .background(SearchTheme.C.canvas)
        .navigationBarBackButtonHidden()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $safariItem) { item in
            SafariSheet(url: item.url)
                .ignoresSafeArea()
        }
        #endif
        .task {
            guard viewModel == nil, let opportunityId else { return }
            let model = OpportunityDetailViewModel(opportunityId: opportunityId, dataSource: dataSource)
            viewModel = model
            await model.load()
        }
    }

    private func detailContent(_ viewModel: OpportunityDetailViewModel) -> some View {
        VStack(spacing: 0) {
            DemoBanner()
            navigationBar(viewModel)
            Group {
                if let detail = viewModel.detail {
                    ScrollView {
                        detailSections(detail, model: viewModel)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                    }
                    .refreshable { await viewModel.load() }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        actionBar(detail, model: viewModel)
                    }
                } else {
                    phaseView(viewModel)
                }
            }
        }
        .background(SearchTheme.C.canvas)
    }

    private func navigationBar(_ viewModel: OpportunityDetailViewModel) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("search.detail.back".localized(bundle: .module))
                        .font(SearchTheme.F.sans(17, .medium))
                }
                .foregroundStyle(SearchTheme.C.navy)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("search.detail.back".localized(bundle: .module))
            Spacer()
            HStack(spacing: 4) {
                Button {
                    Task { await viewModel.toggleSaved() }
                } label: {
                    Image(systemName: viewModel.isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(SearchTheme.C.navy)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: viewModel.isSaved)
                .accessibilityLabel(
                    (viewModel.isSaved ? "search.detail.saved" : "search.detail.save")
                        .localized(bundle: .module)
                )
                .accessibilityAddTraits(viewModel.isSaved ? .isSelected : [])
                .accessibilityIdentifier("search.detail.bookmark")

                if let detail = viewModel.detail {
                    ShareLink(item: ApplyCTA.shareURL(opportunityId: detail.opportunityId)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(SearchTheme.C.navy)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("search.detail.share".localized(bundle: .module))
                    .accessibilityIdentifier("search.detail.share")
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(SearchTheme.C.navy)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func phaseView(_ viewModel: OpportunityDetailViewModel) -> some View {
        switch viewModel.phase {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            InlineErrorBanner(
                message: errorMessage(error),
                retry: { Task { await viewModel.load() } }
            )
            .padding(20)
        case .loaded:
            EmptyView()
        }
    }

    private func detailSections(_ detail: OpportunityDetail, model: OpportunityDetailViewModel) -> some View {
        let opportunity = detail.opportunity
        let status = OpportunityDisplayStatus.resolve(opportunity, now: model.now)
        let summaryText = HTMLText.plainText(from: opportunity.summary.summaryDescription ?? "")
        let applicantTypes = opportunity.summary.applicantTypes ?? []
        return VStack(alignment: .leading, spacing: 0) {
            statusRow(status: status, opportunity: opportunity, now: model.now)

            Text(opportunity.opportunityTitle ?? "search.format.unavailable".localized(bundle: .module))
                .font(SearchTheme.F.title)
                .foregroundStyle(SearchTheme.C.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .accessibilityLabel(
                    opportunity.opportunityTitle == nil
                    ? "search.format.not_available".localized(bundle: .module)
                    : opportunity.opportunityTitle!
                )
                .accessibilityAddTraits(.isHeader)

            Text(opportunity.agencyName ?? opportunity.topLevelAgencyName ?? "search.format.unavailable".localized(bundle: .module))
                .font(SearchTheme.F.label)
                .foregroundStyle(SearchTheme.C.muted)
                .padding(.top, 10)
                .accessibilityLabel(
                    opportunity.agencyName == nil && opportunity.topLevelAgencyName == nil
                    ? "search.format.not_available".localized(bundle: .module)
                    : opportunity.agencyName ?? opportunity.topLevelAgencyName!
                )

            Text(opportunity.opportunityNumber ?? "search.format.unavailable".localized(bundle: .module))
                .font(SearchTheme.F.mono)
                .foregroundStyle(SearchTheme.C.subtle)
                .padding(.top, 4)
                .accessibilityLabel(
                    opportunity.opportunityNumber == nil
                    ? "search.format.not_available".localized(bundle: .module)
                    : opportunity.opportunityNumber!
                )

            factsGrid(opportunity.summary)
                .padding(.top, 20)

            Button {
                let title = opportunity.opportunityTitle ?? opportunity.opportunityNumber ?? ""
                let question = String(
                    format: "search.detail.ask_question_format".localized(bundle: .module),
                    title
                )
                router.push(.answer(question: question))
            } label: {
                Text("search.detail.ask".localized(bundle: .module))
                    .font(SearchTheme.F.sans(15, .medium))
                    .foregroundStyle(SearchTheme.C.navy)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(SearchTheme.C.control, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .accessibilityIdentifier("search.detail.ask")

            sectionHeading("search.detail.eligibility".localized(bundle: .module))
                .padding(.top, 28)

            if !applicantTypes.isEmpty {
                SearchFlowLayout(spacing: 8) {
                    ForEach(applicantTypes, id: \.self) { value in
                        Text(applicantTypeTitle(value))
                            .font(SearchTheme.F.sans(14, .medium))
                            .foregroundStyle(SearchTheme.C.navy)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .background(SearchTheme.C.navyTint, in: Capsule())
                    }
                }
                .padding(.top, 10)
            }
            let eligibilityDescription = HTMLText.plainText(
                from: opportunity.summary.applicantEligibilityDescription ?? ""
            )
            if !eligibilityDescription.isEmpty {
                Text(eligibilityDescription)
                    .font(SearchTheme.F.sans(15))
                    .foregroundStyle(SearchTheme.C.body)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, applicantTypes.isEmpty ? 10 : 12)
            }

            sectionHeading("search.detail.summary".localized(bundle: .module))
                .padding(.top, 28)
            if summaryText.isEmpty {
                unavailableText
                    .padding(.top, 10)
            } else {
                Text(summaryText)
                    .font(SearchTheme.F.answer)
                    .foregroundStyle(SearchTheme.C.body)
                    .lineSpacing(9)
                    .lineLimit(isSummaryExpanded ? nil : 6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                if summaryText.count > 280 {
                    Button(
                        isSummaryExpanded
                        ? "search.detail.show_less".localized(bundle: .module)
                        : "search.detail.show_more".localized(bundle: .module)
                    ) {
                        isSummaryExpanded.toggle()
                    }
                    .font(SearchTheme.F.sans(14, .semibold))
                    .foregroundStyle(SearchTheme.C.navy)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("search.detail.summary_toggle")
                }
            }

            sectionHeading("search.detail.documents".localized(bundle: .module))
                .padding(.top, 28)
            documents(detail.attachments)
                .padding(.top, 10)

            sectionHeading("search.detail.agency_contact".localized(bundle: .module))
                .padding(.top, 28)
            contactSection(opportunity.summary)
                .padding(.top, 8)
        }
    }

    private func statusRow(
        status: OpportunityDisplayStatus,
        opportunity: Opportunity,
        now: Date
    ) -> some View {
        HStack(spacing: 8) {
            StatusChip(status: status.statusChipKey)
            if case let .closingSoon(days) = status {
                Text(days == 0
                     ? "search.detail.closes_today".localized(bundle: .module)
                     : String.localizedStringWithFormat("search.plural.days_left_to_apply".localized(bundle: .module), days))
                    .font(SearchTheme.F.caption)
                    .foregroundStyle(SearchTheme.C.muted)
            } else if status == .open,
                      let days = OpportunityDisplayStatus.daysLeft(for: opportunity, now: now) {
                Text(String.localizedStringWithFormat("search.plural.days_left_to_apply".localized(bundle: .module), days))
                    .font(SearchTheme.F.caption)
                    .foregroundStyle(SearchTheme.C.muted)
            } else if status == .forecasted, let date = opportunity.summary.forecastedCloseDateValue {
                Text(String(format: "search.detail.forecasted_close".localized(bundle: .module), SearchFormatting.shortDate(date)))
                    .font(SearchTheme.F.caption)
                    .foregroundStyle(SearchTheme.C.muted)
            } else if status == .closed, let date = opportunity.summary.closeDateValue {
                Text(String(format: "search.detail.closed_date".localized(bundle: .module), SearchFormatting.shortDate(date)))
                    .font(SearchTheme.F.caption)
                    .foregroundStyle(SearchTheme.C.muted)
            }
            Spacer(minLength: 0)
        }
    }

    private func factsGrid(_ summary: OpportunitySummary) -> some View {
        let facts: [(String, String?)] = [
            ("search.detail.award_ceiling", summary.awardCeiling.map(SearchFormatting.fullCurrency)),
            ("search.detail.award_floor", summary.awardFloor.map(SearchFormatting.fullCurrency)),
            ("search.detail.expected_awards", summary.expectedNumberOfAwards.map(String.init)),
            ("search.detail.total_funding", summary.estimatedTotalProgramFunding.map(SearchFormatting.fullCurrency)),
            ("search.detail.close_date", summary.closeDateValue.map(SearchFormatting.shortDate)),
            ("search.detail.cost_sharing", summary.isCostSharing.map {
                ($0 ? "search.detail.required" : "search.detail.not_required").localized(bundle: .module)
            })
        ]
        return SearchCard {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(alignment: .top, spacing: 0) {
                        factCell(facts[row * 2])
                        factCell(facts[row * 2 + 1])
                    }
                    if row < 2 {
                        Rectangle()
                            .fill(SearchTheme.C.lineSoft)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(-SearchTheme.S.l)
        }
    }

    private func factCell(_ fact: (String, String?)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(fact.0.localized(bundle: .module))
                .font(SearchTheme.F.sans(12))
                .foregroundStyle(SearchTheme.C.subtle)
            Text(fact.1 ?? "search.format.unavailable".localized(bundle: .module))
                .font(SearchTheme.F.sans(15, .semibold))
                .foregroundStyle(SearchTheme.C.ink)
                .accessibilityLabel(
                    fact.1 == nil
                    ? "search.format.not_available".localized(bundle: .module)
                    : fact.1!
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func documents(_ attachments: [OpportunityAttachment]) -> some View {
        Group {
            if attachments.isEmpty {
                Text("search.detail.no_documents".localized(bundle: .module))
                    .font(SearchTheme.F.label)
                    .foregroundStyle(SearchTheme.C.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                        attachmentRow(attachment)
                        if index < attachments.count - 1 {
                            Rectangle()
                                .fill(SearchTheme.C.lineSoft)
                                .frame(height: 1)
                                .padding(.leading, 62)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(SearchTheme.C.line, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func attachmentRow(_ attachment: OpportunityAttachment) -> some View {
        let filename = attachment.fileName ?? "search.format.unavailable".localized(bundle: .module)
        let fileType = (attachment.fileType ?? URL(fileURLWithPath: filename).pathExtension)
            .uppercased()
        let content = HStack(spacing: 12) {
            Text(fileType.isEmpty ? "search.detail.file".localized(bundle: .module) : fileType)
                .font(SearchTheme.F.monoFont(9, .semibold, relativeTo: .caption2))
                .foregroundStyle(SearchTheme.C.red)
                .frame(width: 34, height: 40, alignment: .bottom)
                .padding(.bottom, 4)
                .background(SearchTheme.C.canvas, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(SearchTheme.C.line, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(SearchTheme.F.sans(15, .semibold))
                    .foregroundStyle(SearchTheme.C.ink)
                    .multilineTextAlignment(.leading)
                Text(attachment.mimeType ?? fileType)
                    .font(SearchTheme.F.caption)
                    .foregroundStyle(SearchTheme.C.subtle)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)

        if let url = absoluteWebURL(attachment.downloadPath) {
            Button {
                open(url)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                attachment.fileName == nil
                ? "search.format.not_available".localized(bundle: .module)
                : filename
            )
        } else {
            content
        }
    }

    private func contactSection(_ summary: OpportunitySummary) -> some View {
        let description = HTMLText.plainText(from: summary.agencyContactDescription ?? "")
        let email = summary.agencyEmailAddress
        return Group {
            if description.isEmpty, email?.isEmpty != false {
                Text("search.detail.contact_unavailable".localized(bundle: .module))
                    .foregroundStyle(SearchTheme.C.muted)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if !description.isEmpty {
                        Text(description)
                            .foregroundStyle(SearchTheme.C.body)
                            .lineSpacing(8)
                    }
                    if let email, !email.isEmpty, let url = URL(string: "mailto:\(email)") {
                        Link(email, destination: url)
                            .foregroundStyle(SearchTheme.C.navy)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }
        }
        .font(SearchTheme.F.label)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(SearchTheme.F.section)
            .foregroundStyle(SearchTheme.C.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private var unavailableText: some View {
        Text("search.format.unavailable".localized(bundle: .module))
            .font(SearchTheme.F.answer)
            .foregroundStyle(SearchTheme.C.muted)
            .accessibilityLabel("search.format.not_available".localized(bundle: .module))
    }

    private func applicantTypeTitle(_ value: String) -> String {
        let key = "search.applicant_type.\(value)"
        let translated = key.localized(bundle: .module)
        guard translated != key else {
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return translated
    }

    @ViewBuilder
    private func actionBar(_ detail: OpportunityDetail, model: OpportunityDetailViewModel) -> some View {
        let action = ApplyCTA.resolve(detail: detail, session: sessionStore.state, now: model.now)
        VStack(spacing: 8) {
            if let error = model.saveError ?? model.actionError {
                InlineErrorBanner(message: errorMessage(error))
            }
            switch action {
            case let .startApplication(competition):
                Button {
                    Task {
                        guard let applicationId = await model.startApplication(competition) else { return }
                        router.push(.application(id: applicationId), in: .apply)
                        router.tab = .apply
                    }
                } label: {
                    ctaLabel("search.detail.start_application", isLoading: model.isStartingApplication)
                }
                .buttonStyle(SearchPrimaryButtonStyle(enabled: !model.isStartingApplication))
                .disabled(model.isStartingApplication)
                .accessibilityIdentifier("search.detail.cta")
            case .signInToApply:
                Button {
                    Task { await sessionStore.signIn(pivRequired: false) }
                } label: {
                    ctaLabel("search.detail.sign_in_to_apply")
                }
                .buttonStyle(SearchPrimaryButtonStyle())
                .accessibilityIdentifier("search.detail.cta")
            case let .applyOnGrantsGov(url):
                Button {
                    open(url)
                } label: {
                    ctaLabel("search.detail.apply_grants_gov")
                }
                .buttonStyle(SearchPrimaryButtonStyle())
                .accessibilityIdentifier("search.detail.cta")
            case .closed:
                VStack(spacing: 8) {
                    Button("search.detail.applications_closed".localized(bundle: .module), action: {})
                        .buttonStyle(SearchPrimaryButtonStyle(enabled: false))
                        .disabled(true)
                        .accessibilityIdentifier("search.detail.cta")
                    Text("search.detail.closed_explanation".localized(bundle: .module))
                        .font(SearchTheme.F.caption)
                        .foregroundStyle(SearchTheme.C.muted)
                }
            case .notYetOpen:
                VStack(spacing: 8) {
                    Button("search.detail.not_open_yet".localized(bundle: .module), action: {})
                        .buttonStyle(SearchPrimaryButtonStyle(enabled: false))
                        .disabled(true)
                        .accessibilityIdentifier("search.detail.cta")
                    Text("search.detail.forecasted_explanation".localized(bundle: .module))
                        .font(SearchTheme.F.caption)
                        .foregroundStyle(SearchTheme.C.muted)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(SearchTheme.C.canvas.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SearchTheme.C.line)
                .frame(height: 1)
        }
    }

    private func ctaLabel(_ key: String, isLoading: Bool = false) -> some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .tint(.white)
            }
            Text(key.localized(bundle: .module))
        }
        .frame(maxWidth: .infinity)
    }

    private func errorMessage(_ error: GrantsError) -> String {
        let key: String
        switch error {
        case .offline: key = "search.error.offline"
        case .unauthorized: key = "search.error.unauthorized"
        case .notFound: key = "search.error.not_found"
        case .server: key = "search.error.server"
        case .decoding: key = "search.error.decoding"
        }
        return key.localized(bundle: .module)
    }

    private func absoluteWebURL(_ value: String?) -> URL? {
        guard
            let value,
            let components = URLComponents(string: value),
            ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
            components.host != nil
        else {
            return nil
        }
        return components.url
    }

    private func open(_ url: URL) {
        #if os(iOS)
        safariItem = SafariItem(url: url)
        #endif
    }
}

private struct SafariItem: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
private struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
