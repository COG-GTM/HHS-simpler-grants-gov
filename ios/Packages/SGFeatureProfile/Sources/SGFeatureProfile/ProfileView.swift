import SGCore
import SGDesign
import SGModels
import SwiftUI

public struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.grantsDataSource) private var dataSource
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let appEnvironment = AppEnvironment()
    @State private var model: ProfileModel
    @AppStorage("sg.profile.notifications.deadlines") private var deadlinesEnabled = true
    @AppStorage("sg.profile.notifications.saved_searches") private var savedSearchesEnabled = true
    @State private var isSignInRunning = false
    @State private var isSavedSheetPresented = false
    private let referenceDateOverride: Date?

    public init() {
        self.init(model: ProfileModel())
    }

    public init(model: ProfileModel, referenceDate: Date? = nil) {
        _model = State(initialValue: model)
        referenceDateOverride = referenceDate
    }

    private var signedInUserId: String? {
        guard case let .signedIn(user) = session.state else { return nil }
        return user.userId
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            ScrollView {
                VStack(alignment: .leading, spacing: SG.S.xl) {
                    Text("profile.title".localized(bundle: .module))
                        .font(SG.F.largeTitle)
                        .foregroundStyle(SG.C.ink)
                        .accessibilityAddTraits(.isHeader)

                    if case let .signedIn(user) = session.state {
                        signedInContent(user)
                    } else {
                        signInContent
                    }

                    sharedSections
                    Text("profile.footer".localized(bundle: .module))
                        .font(SG.F.caption)
                        .foregroundStyle(SG.C.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, SG.S.margin)
                .padding(.top, SG.S.s)
                .padding(.bottom, SG.S.xl + 56)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(SG.C.canvas.ignoresSafeArea())
        .sgHideNavigationBar()
        .task(id: signedInUserId) {
            guard let userId = signedInUserId else {
                model.reset()
                return
            }
            if model.loadedUserId != userId || model.loadError != nil {
                if model.loadedUserId != userId {
                    model.reset()
                }
                await model.load(from: dataSource, userId: userId)
            }
        }
        .sheet(isPresented: $isSavedSheetPresented) {
            savedOpportunitiesSheet
        }
    }

    private func signedInContent(_ user: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: SG.S.xl) {
            identity(user)

            if model.loadError != nil {
                InlineErrorBanner(
                    message: "profile.load_error".localized(bundle: .module),
                    retry: {
                        Task {
                            await model.load(from: dataSource, userId: user.userId)
                        }
                    }
                )
                .accessibilityIdentifier("profile.load_error")
            }

            VStack(alignment: .leading, spacing: SG.S.s) {
                sectionHeading("profile.organization.heading")
                Card {
                    VStack(alignment: .leading, spacing: SG.S.m) {
                        Text(model.organization?.samGovEntity?.legalBusinessName ?? "profile.organization.unavailable".localized(bundle: .module))
                            .font(SG.F.serif(17))
                            .foregroundStyle(SG.C.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("profile.organization")
                        organizationIdentifiers
                    }
                }
            }

            Button {
                isSavedSheetPresented = true
            } label: {
                HStack(spacing: SG.S.s) {
                    Text("profile.saved.title".localized(bundle: .module))
                        .font(SG.F.sans(16, .medium))
                        .foregroundStyle(SG.C.ink)
                    Spacer()
                    Text(String(
                        format: "profile.saved.count".localized(bundle: .module),
                        locale: Locale(identifier: "en_US"),
                        model.savedOpportunityIds.count
                    ))
                    .font(SG.F.sans(14, .medium))
                    .foregroundStyle(SG.C.muted)
                    Image(systemName: "chevron.right")
                        .font(SG.F.sans(12, .semibold))
                        .foregroundStyle(SG.C.muted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, SG.S.l)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(SG.C.surface, in: RoundedRectangle(cornerRadius: SG.R.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: SG.R.card, style: .continuous).stroke(SG.C.line, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.saved_opportunities")

            notifications

            Button {
                Task { await session.signOut() }
            } label: {
                Text("profile.sign_out".localized(bundle: .module))
                    .font(SG.F.sans(16, .semibold))
                    .foregroundStyle(SG.C.red)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(SG.C.surface, in: RoundedRectangle(cornerRadius: SG.R.button, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: SG.R.button, style: .continuous).stroke(SG.C.line, lineWidth: 1))
                }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.sign_out")
        }
    }

    private func identity(_ user: UserProfile) -> some View {
        let firstName = user.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lastName = user.lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        let initials = [firstName.first, lastName.first].compactMap { $0 }.map(String.init).joined()

        return HStack(spacing: SG.S.m) {
            Text(initials.isEmpty ? String(user.email.prefix(1)).uppercased() : initials.uppercased())
                .font(SG.F.sans(20, .semibold))
                .foregroundStyle(SG.C.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: 56, height: 56)
                .background(SG.C.navyTint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName.isEmpty ? user.email : displayName)
                    .font(SG.F.sans(18, .semibold))
                    .foregroundStyle(SG.C.ink)
                Text(user.email)
                    .font(SG.F.sans(14))
                    .foregroundStyle(SG.C.muted)
                Text("profile.identity.login_gov".localized(bundle: .module))
                    .font(SG.F.sans(12, .semibold))
                    .foregroundStyle(SG.C.green)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.identity")
    }

    private var samStatus: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let status = SamRegistrationStatus.evaluate(
                expirationDate: model.organization?.samGovEntity?.expirationDate,
                today: referenceDateOverride ?? context.date
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("profile.organization.sam_gov".localized(bundle: .module))
                    .font(SG.F.sans(13))
                    .foregroundStyle(SG.C.subtle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                HStack(spacing: SG.S.xs) {
                    Image(systemName: status.iconName)
                        .font(SG.F.sans(12, .semibold))
                        .foregroundStyle(status.tintColor)
                        .accessibilityHidden(true)
                    Text(status.localizedText)
                        .font(SG.F.sans(13, .semibold))
                        .foregroundStyle(status.tintColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var organizationIdentifiers: some View {
        let uei = fact(
            title: "profile.organization.uei",
            value: model.organization?.samGovEntity?.uei ?? "profile.value_unavailable".localized(bundle: .module),
            monospaced: true,
            valueAccessibilityIdentifier: "profile.uei"
        )
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: SG.S.m) {
                uei
                samStatus
            }
        } else {
            HStack(alignment: .top, spacing: SG.S.l) {
                uei
                samStatus
            }
        }
    }

    private func fact(
        title: String,
        value: String,
        monospaced: Bool = false,
        valueAccessibilityIdentifier: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.localized(bundle: .module))
                .font(SG.F.sans(13))
                .foregroundStyle(SG.C.subtle)
            factValue(value, monospaced: monospaced, accessibilityIdentifier: valueAccessibilityIdentifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func factValue(
        _ value: String,
        monospaced: Bool,
        accessibilityIdentifier: String?
    ) -> some View {
        if let accessibilityIdentifier {
            Text(value)
                .font(monospaced ? .system(size: 13, weight: .medium, design: .monospaced) : SG.F.sans(14, .semibold))
                .foregroundStyle(SG.C.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            Text(value)
                .font(monospaced ? .system(size: 13, weight: .medium, design: .monospaced) : SG.F.sans(14, .semibold))
                .foregroundStyle(SG.C.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: SG.S.s) {
            sectionHeading("profile.notifications.heading")
            Card {
                VStack(spacing: 0) {
                    Toggle("profile.notifications.deadlines".localized(bundle: .module), isOn: $deadlinesEnabled)
                        .font(SG.F.sans(15))
                        .frame(minHeight: 48)
                        .accessibilityIdentifier("profile.notifications.deadlines")
                    Divider().overlay(SG.C.lineSoft)
                    Toggle("profile.notifications.saved_searches".localized(bundle: .module), isOn: $savedSearchesEnabled)
                        .font(SG.F.sans(15))
                        .frame(minHeight: 48)
                        .accessibilityIdentifier("profile.notifications.saved_searches")
                }
                Text("profile.notifications.note".localized(bundle: .module))
                    .font(SG.F.caption)
                    .foregroundStyle(SG.C.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SG.S.s)
            }
        }
    }

    private var signInContent: some View {
        VStack(alignment: .leading, spacing: SG.S.m) {
            Card {
                VStack(alignment: .leading, spacing: SG.S.s) {
                    Text("profile.signed_out.title".localized(bundle: .module))
                        .font(SG.F.serif(19))
                        .foregroundStyle(SG.C.ink)
                    Text("profile.signed_out.body".localized(bundle: .module))
                        .font(SG.F.bodyText)
                        .foregroundStyle(SG.C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        signIn()
                    } label: {
                        HStack(spacing: SG.S.s) {
                            if isSignInRunning {
                                ProgressView().tint(.white)
                            }
                            Text("profile.sign_in".localized(bundle: .module))
                        }
                        .frame(minHeight: 52)
                    }
                    .buttonStyle(PrimaryButton(enabled: !isSignInRunning))
                    .disabled(isSignInRunning)
                    .accessibilityIdentifier("profile.sign_in")
                }
            }

            if let error = session.lastError {
                InlineErrorBanner(
                    message: Self.signInErrorMessage(for: error).localized(bundle: .module),
                    retry: signIn
                )
            }
        }
    }

    private var sharedSections: some View {
        VStack(alignment: .leading, spacing: SG.S.xl) {
            VStack(alignment: .leading, spacing: SG.S.s) {
                sectionHeading("profile.data_mode.heading")
                Card {
                    HStack(alignment: .top, spacing: SG.S.s) {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(SG.C.navy)
                            .accessibilityHidden(true)
                        Text(dataModeDescription)
                            .font(SG.F.sans(14))
                            .foregroundStyle(SG.C.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }

            VStack(alignment: .leading, spacing: SG.S.s) {
                sectionHeading("profile.about.heading")
                Card {
                    VStack(alignment: .leading, spacing: SG.S.m) {
                        aboutPoint(title: "profile.about.data.title", body: "profile.about.data.body")
                        aboutPoint(title: "profile.about.ai.title", body: "profile.about.ai.body")
                        aboutPoint(title: "profile.about.affiliation.title", body: "profile.about.affiliation.body")
                    }
                }
            }

            Button {
                router.push(.roadmap, in: .profile)
            } label: {
                HStack(spacing: SG.S.s) {
                    Text("profile.roadmap.row_title".localized(bundle: .module))
                        .font(SG.F.sans(16, .medium))
                        .foregroundStyle(SG.C.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(SG.F.sans(12, .semibold))
                        .foregroundStyle(SG.C.muted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, SG.S.l)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(SG.C.surface, in: RoundedRectangle(cornerRadius: SG.R.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: SG.R.card, style: .continuous).stroke(SG.C.line, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.roadmap")
        }
    }

    private var dataModeDescription: String {
        switch appEnvironment.dataMode {
        case .sample:
            "profile.data_mode.sample".localized(bundle: .module)
        case let .live(baseURL):
            String(
                format: "profile.data_mode.live".localized(bundle: .module),
                locale: Locale(identifier: "en_US"),
                baseURL.hostAndPort
            )
        }
    }

    private var savedOpportunitiesSheet: some View {
        NavigationStack {
            Group {
                if model.savedOpportunities.isEmpty {
                    ContentUnavailableView(
                        "profile.saved.empty.title".localized(bundle: .module),
                        systemImage: "bookmark",
                        description: Text("profile.saved.empty.body".localized(bundle: .module))
                    )
                } else {
                    List(model.savedOpportunities) { opportunity in
                        Text(opportunity.title)
                            .font(SG.F.sans(15))
                            .padding(.vertical, SG.S.xs)
                    }
                }
            }
            .navigationTitle("profile.saved.title".localized(bundle: .module))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("profile.saved.done".localized(bundle: .module)) {
                        isSavedSheetPresented = false
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    private func sectionHeading(_ key: String) -> some View {
        Text(key.localized(bundle: .module))
            .font(SG.F.overline)
            .textCase(.uppercase)
            .tracking(0.08 * 12)
            .foregroundStyle(SG.C.muted)
            .accessibilityAddTraits(.isHeader)
    }

    private func aboutPoint(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: SG.S.xs) {
            Text(title.localized(bundle: .module))
                .font(SG.F.sans(15, .semibold))
                .foregroundStyle(SG.C.ink)
            Text(body.localized(bundle: .module))
                .font(SG.F.sans(14))
                .foregroundStyle(SG.C.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func signIn() {
        guard !isSignInRunning else { return }
        isSignInRunning = true
        Task {
            await session.signIn(pivRequired: false)
            isSignInRunning = false
        }
    }

    private static func signInErrorMessage(for error: GrantsError) -> String {
        switch error {
        case .unauthorized:
            "profile.sign_in_error.unauthorized"
        case .notFound:
            "profile.sign_in_error.not_found"
        case .offline:
            "profile.sign_in_error.offline"
        case .server:
            "profile.sign_in_error.server"
        case .decoding:
            "profile.sign_in_error.generic"
        }
    }
}

private extension URL {
    var hostAndPort: String {
        guard let host else { return absoluteString }
        return port.map { "\(host):\($0)" } ?? host
    }
}

#Preview("Profile · signed in") {
    ProfileView()
        .environment(SessionStore(authenticator: PreviewAuthenticator()))
        .environment(AppRouter(tab: .profile))
}
