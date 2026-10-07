import SGAsk
import SGCore
import SGDesign
import SGModels
import SwiftUI

public struct AskHomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.grantsDataSource) private var dataSource
    @AppStorage("sg.ask.eligibility") private var eligibilityRaw = EligibilityOption.nonprofit.rawValue
    @AppStorage("sg.ask.recentQuestions") private var recentQuestionsRaw = ""
    @FocusState private var composerFocused: Bool
    @State private var text = ""
    @State private var applicationDraft: ApplicationDraft?
    @State private var handledLaunchQuestion = false

    public init() {}

    public init(initialText: String) {
        _text = State(initialValue: initialText)
    }

    private var eligibility: EligibilityOption {
        EligibilityOption(rawValue: eligibilityRaw) ?? .nonprofit
    }

    private var recentQuestions: [String] {
        RecentQuestions.decode(recentQuestionsRaw)
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GovStyleHeader(initials: initials, onProfile: { router.tab = .profile })
                        .accessibilityIdentifier("ask.home.profile")

                    Text(verbatim: "ask.home.title".localized(bundle: .module))
                        .font(SG.F.largeTitle)
                        .foregroundStyle(SG.C.ink)
                        .padding(.top, 40)
                        .accessibilityAddTraits(.isHeader)

                    Text(verbatim: "ask.home.subtitle".localized(bundle: .module))
                        .font(SG.F.sans(15))
                        .foregroundStyle(SG.C.muted)
                        .lineSpacing(3)
                        .padding(.top, 10)

                    composer
                        .padding(.top, 24)

                    Text(verbatim: "ask.home.try_asking".localized(bundle: .module))
                        .font(SG.F.sans(13, .semibold))
                        .foregroundStyle(SG.C.muted)
                        .padding(.top, 28)

                    suggestions
                        .padding(.top, 10)

                    if !recentQuestions.isEmpty {
                        recentQuestionsSection
                            .padding(.top, 28)
                    }

                    if let applicationDraft {
                        applicationCard(applicationDraft)
                            .padding(.top, 28)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SG.C.canvas)
        .task {
            await loadApplicationDraft()
        }
        .onAppear(perform: handleLaunchQuestion)
        #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                "ask.home.placeholder".localized(bundle: .module),
                text: $text,
                axis: .vertical
            )
            .font(SG.F.sans(17))
            .foregroundStyle(SG.C.ink)
            .lineLimit(3, reservesSpace: true)
            .focused($composerFocused)
            .accessibilityIdentifier("ask.composer.field")
            .onSubmit { sendQuestion(text) }
            .onChange(of: text) { _, newValue in
                guard newValue.contains("\n") || newValue.contains("\r") else { return }
                sendQuestion(newValue)
            }

            HStack(alignment: .center) {
                eligibilityMenu
                Spacer(minLength: 8)

                Button {
                    sendQuestion(text)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            AskComposer.normalized(text) == nil ? SG.C.disabled : SG.C.navy,
                            in: Circle()
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(AskComposer.normalized(text) == nil)
                .accessibilityLabel("ask.home.send".localized(bundle: .module))
                .accessibilityIdentifier("ask.composer.send")
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(SG.C.surface)
                .shadow(
                    color: Color(
                        .sRGB,
                        red: 20.0 / 255.0,
                        green: 23.0 / 255.0,
                        blue: 31.0 / 255.0
                    )
                    .opacity(0.10),
                    radius: 12,
                    x: 0,
                    y: 8
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(SG.C.line, lineWidth: 1)
        }
    }

    private var eligibilityMenu: some View {
        Menu {
            Picker(
                "ask.home.eligibility.accessibility".localized(bundle: .module),
                selection: $eligibilityRaw
            ) {
                ForEach(EligibilityOption.allCases) { option in
                    Text(verbatim: option.localizationKey.localized(bundle: .module))
                        .tag(option.rawValue)
                }
            }
        } label: {
            Text(verbatim: eligibilityLabel)
                .font(SG.F.sans(13))
                .foregroundStyle(SG.C.muted)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(SG.C.canvas, in: Capsule())
                .contentShape(Capsule())
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(
                format: "ask.home.eligibility.accessibility".localized(bundle: .module),
                eligibility.localizationKey.localized(bundle: .module)
            )
        )
        .accessibilityHint("ask.home.eligibility.hint".localized(bundle: .module))
        .accessibilityIdentifier("ask.composer.eligibility")
    }

    private var eligibilityLabel: String {
        String(
            format: "ask.home.eligibility_label".localized(bundle: .module),
            eligibility.localizationKey.localized(bundle: .module)
        )
    }

    private var suggestions: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                Button {
                    sendQuestion("ask.home.suggestion.\(index)".localized(bundle: .module))
                } label: {
                    HStack(spacing: 12) {
                        Text(verbatim: "ask.home.suggestion.\(index)".localized(bundle: .module))
                            .font(SG.F.sans(16))
                            .foregroundStyle(SG.C.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(SG.C.subtle)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(SG.C.line)
                        .frame(height: 1)
                }
                .accessibilityIdentifier("ask.suggestion.\(index)")
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SG.C.line)
                .frame(height: 1)
        }
    }

    private var recentQuestionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: "ask.home.recent.title".localized(bundle: .module))
                    .font(SG.F.section)
                    .foregroundStyle(SG.C.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("ask.home.recent.clear".localized(bundle: .module)) {
                    recentQuestionsRaw = RecentQuestions.encode([])
                }
                .font(SG.F.sans(15, .medium))
                .foregroundStyle(SG.C.navy)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask.recent.clear")
            }

            VStack(spacing: 0) {
                ForEach(Array(recentQuestions.enumerated()), id: \.offset) { index, question in
                    Button {
                        sendQuestion(question)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(SG.C.subtle)
                                .accessibilityHidden(true)
                            Text(verbatim: question)
                                .font(SG.F.sans(16))
                                .foregroundStyle(SG.C.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(SG.C.line)
                            .frame(height: 1)
                    }
                    .accessibilityIdentifier("ask.recent.\(index)")
                }
            }
        }
    }

    private func applicationCard(_ draft: ApplicationDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "ask.home.application.overline".localized(bundle: .module))
                .font(SG.F.sans(12, .semibold))
                .tracking(0.72)
                .foregroundStyle(.white.opacity(0.8))

            Text(verbatim: draft.title)
                .font(SG.F.cardTitle)
                .foregroundStyle(.white)

            HStack(alignment: .center) {
                let forms = String(
                    format: "ask.home.application.forms".localized(bundle: .module),
                    draft.completedForms,
                    draft.totalForms
                )
                if let dueDate = draft.dueDate {
                let due = String(
                    format: "ask.home.application.due".localized(bundle: .module),
                    dueDate
                )
                    Text(
                        verbatim: String(
                            format: "ask.home.application.progress".localized(bundle: .module),
                            forms,
                            due
                        )
                    )
                    .font(SG.F.sans(14))
                    .foregroundStyle(.white.opacity(0.85))
                } else {
                    Text(verbatim: forms)
                        .font(SG.F.sans(14))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 8)
                Button("ask.home.application.continue".localized(bundle: .module)) {
                    router.push(.application(id: draft.id), in: .apply)
                    router.tab = .apply
                }
                .font(SG.F.sans(14, .semibold))
                .foregroundStyle(SG.C.navy)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(.white, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask.cta.continue")
            }
            .padding(.top, 8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SG.C.navy, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var initials: String {
        guard case let .signedIn(user) = sessionStore.state else {
            return "ask.home.guest_initials".localized(bundle: .module)
        }
        let first = user.firstName?.trimmingCharacters(in: .whitespacesAndNewlines).first
        let last = user.lastName?.trimmingCharacters(in: .whitespacesAndNewlines).first
        if let first, let last {
            return String([first, last]).uppercased()
        }
        if let first { return String(first).uppercased() }
        if let last { return String(last).uppercased() }
        let fallbackInitial = "ask.home.guest_initials".localized(bundle: .module).first ?? "G"
        return String(user.email.first ?? fallbackInitial).uppercased()
    }

    private func sendQuestion(_ rawQuestion: String) {
        guard let question = AskComposer.normalized(rawQuestion) else { return }
        recentQuestionsRaw = RecentQuestions.encode(
            RecentQuestions.adding(question, to: recentQuestions)
        )
        text = ""
        composerFocused = false
        router.push(.answer(question: question), in: .ask)
    }

    private func handleLaunchQuestion() {
        guard !handledLaunchQuestion else { return }
        handledLaunchQuestion = true
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
            if let index = arguments.firstIndex(of: "-SGAskPrefill"),
               arguments.indices.contains(index + 1) {
                text = arguments[index + 1]
            }
            if arguments.contains("-SGAskSeedRecents") {
                recentQuestionsRaw = RecentQuestions.encode([
                    "How can a rural clinic expand addiction treatment?",
                    "Funding for a community health nonprofit",
                    "Grants for local climate resilience projects"
                ])
            }
        #endif
        guard let index = arguments.firstIndex(of: "-SGAskQuestion"),
              arguments.indices.contains(index + 1) else {
            return
        }
        sendQuestion(arguments[index + 1])
    }

    @MainActor
    private func loadApplicationDraft() async {
        do {
            let applications = try await dataSource.applications()
            guard let summary = applications.first(where: {
                $0.applicationStatus.caseInsensitiveCompare("submitted") != .orderedSame
            }) else {
                applicationDraft = nil
                return
            }
            let application = try await dataSource.application(id: summary.applicationId)
            let title = summary.competition.opportunity.opportunityTitle
                ?? summary.applicationName
                ?? summary.competition.competitionTitle
                ?? "ask.home.application.untitled".localized(bundle: .module)
            applicationDraft = ApplicationDraft(
                id: summary.applicationId,
                title: title,
                completedForms: application.applicationForms.filter {
                    $0.applicationFormStatus.caseInsensitiveCompare("complete") == .orderedSame
                }.count,
                totalForms: application.applicationForms.count,
                dueDate: Self.formattedDueDate(summary.competition.closingDate)
            )
        } catch {
            applicationDraft = nil
        }
    }

    private static func formattedDueDate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        input.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = input.date(from: raw) else { return nil }
        let output = DateFormatter()
        output.locale = Locale.current
        output.dateFormat = "MMM d"
        output.timeZone = TimeZone(secondsFromGMT: 0)
        return output.string(from: date)
    }
}

private struct ApplicationDraft {
    let id: String
    let title: String
    let completedForms: Int
    let totalForms: Int
    let dueDate: String?
}

public struct AnswerView: View {
    private enum Phase {
        case loading
        case loaded(AskAnswer)
        case failed
    }

    enum Preloaded {
        case answer(AskAnswer)
        case failed
    }

    @Environment(AppRouter.self) private var router
    @Environment(\.askEngine) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @AppStorage("sg.ask.eligibility") private var eligibilityRaw = EligibilityOption.nonprofit.rawValue
    @AppStorage("sg.ask.recentQuestions") private var recentQuestionsRaw = ""
    @State private var phase = Phase.loading
    @State private var didSkipInitialLoad = false
    @State private var removedFilters: Set<InferredFilter> = []
    @State private var highlightedCitation: Int?
    @State private var followupText = ""
    @State private var reloadCounter = 0
    @FocusState private var followupFocused: Bool
    private let question: String
    private let skipsInitialLoad: Bool

    public init(question: String) {
        self.question = question
        self.skipsInitialLoad = false
    }

    init(question: String, preloaded: Preloaded) {
        self.question = question
        self.skipsInitialLoad = true

        switch preloaded {
        case let .answer(answer):
            _phase = State(initialValue: .loaded(answer))
        case .failed:
            _phase = State(initialValue: .failed)
        }
    }

    private var eligibility: EligibilityOption {
        EligibilityOption(rawValue: eligibilityRaw) ?? .nonprofit
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            answerNavigationBar

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        questionBubble

                        switch phase {
                        case .loading:
                            LoadingAnswerView(reduceMotion: reduceMotion)
                                .accessibilityIdentifier("ask.answer.loading")
                        case let .loaded(answer):
                            if answer.citations.isEmpty || answer.paragraphs.isEmpty {
                                EmptyStateView(
                                    title: "ask.answer.empty.title".localized(bundle: .module),
                                    message: "ask.answer.empty.message".localized(bundle: .module),
                                    actionTitle: "ask.answer.empty.action".localized(bundle: .module),
                                    action: { router.tab = .search }
                                )
                                .accessibilityIdentifier("ask.answer.empty")
                            } else {
                                answerContent(answer, proxy: proxy)
                            }
                        case .failed:
                            InlineErrorBanner(
                                message: "ask.answer.error".localized(bundle: .module),
                                retry: { reloadCounter += 1 }
                            )
                            .accessibilityIdentifier("ask.answer.error")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "sgcite" else { return .discarded }
                    let value = url.host ?? String(url.path.dropFirst())
                    guard let index = Int(value),
                          case let .loaded(answer) = phase,
                          answer.citations.contains(where: { $0.index == index }) else {
                        return .discarded
                    }
                    withAnimation(.easeInOut) {
                        proxy.scrollTo("citation-\(index)", anchor: .center)
                    }
                    highlightCitation(index)
                    return .handled
                })
            }
        }
        .background(SG.C.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            followupComposer
        }
        .task(id: AnswerLoadKey(removedFilters: removedFilters, reloadCounter: reloadCounter)) {
            if skipsInitialLoad && !didSkipInitialLoad {
                didSkipInitialLoad = true
                return
            }
            await loadAnswer()
        }
        #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .navigationBarBackButtonHidden(true)
        #endif
    }

    @ViewBuilder
    private var answerNavigationBar: some View {
        let backLabel = "ask.answer.back".localized(bundle: .module)
        let title = "ask.answer.title".localized(bundle: .module)
        let newLabel = "ask.answer.new".localized(bundle: .module)

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text(verbatim: backLabel)
                        }
                        .font(SG.F.sans(15, .medium))
                        .foregroundStyle(SG.C.navy)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(backLabel)

                    Spacer(minLength: 12)

                    Button(newLabel) {
                        router.popToRoot(router.tab)
                    }
                    .font(SG.F.sans(15, .medium))
                    .foregroundStyle(SG.C.navy)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .buttonStyle(.plain)
                }

                Text(verbatim: title)
                    .font(SG.F.sans(17, .semibold))
                    .foregroundStyle(SG.C.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        } else {
            SGNavBar(
                backLabel: backLabel,
                title: title,
                trailingAction: newLabel,
                onTrailing: { router.popToRoot(router.tab) }
            )
            .padding(.horizontal, 12)
            .frame(height: 44)
        }
    }

    private var questionBubble: some View {
        HStack {
            Spacer(minLength: 0)
            Text(verbatim: question)
                .font(SG.F.sans(16))
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background {
                    UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(
                            topLeading: 20,
                            bottomLeading: 20,
                            bottomTrailing: 6,
                            topTrailing: 20
                        ),
                        style: .continuous
                    )
                    .fill(SG.C.navy)
                }
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.8 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                format: "ask.answer.you_asked".localized(bundle: .module),
                question
            )
        )
    }

    @ViewBuilder
    private func answerContent(_ answer: AskAnswer, proxy: ScrollViewProxy) -> some View {
        let visibleFilters = answer.intent.inferredFilters.filter { !removedFilters.contains($0) }
        if !visibleFilters.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "ask.answer.understood".localized(bundle: .module))
                    .font(SG.F.sans(13))
                    .foregroundStyle(SG.C.muted)

                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(visibleFilters) { filter in
                        Button {
                            removedFilters.insert(filter)
                        } label: {
                            HStack(spacing: 6) {
                                Text(verbatim: filter.label)
                                    .font(SG.F.sans(14, .medium))
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(SG.C.ink)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(.white, in: Capsule())
                            .overlay(Capsule().stroke(SG.C.control, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            String(
                                format: "ask.answer.remove_filter".localized(bundle: .module),
                                filter.label
                            )
                        )
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 12) {
            Text(
                verbatim: String(
                    format: "ask.answer.listings".localized(bundle: .module),
                    answer.citations.count
                )
            )
            .font(SG.F.sans(12, .semibold))
            .tracking(0.72)
            .foregroundStyle(SG.C.muted)

            ForEach(Array(answer.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                AnswerParagraphText(paragraph: paragraph, citations: answer.citations) { index in
                    highlightCitation(index)
                    withAnimation(.easeInOut) {
                        proxy.scrollTo("citation-\(index)", anchor: .center)
                    }
                }
            }
        }

        VStack(spacing: 10) {
            ForEach(answer.citations) { citation in
                citationCard(citation)
                    .id("citation-\(citation.index)")
            }
        }

        Text(verbatim: "ask.answer.disclaimer".localized(bundle: .module))
            .font(SG.F.sans(12))
            .foregroundStyle(SG.C.subtle)

        if answer.totalMatches > 0 {
            Button {
                let request = AnswerSearchRequest.make(
                    intent: answer.intent,
                    removing: removedFilters
                )
                router.push(.results(request), in: .search)
                router.tab = .search
            } label: {
                Text(
                    verbatim: String(
                        format: "ask.answer.see_all".localized(bundle: .module),
                        answer.totalMatches
                    )
                )
                .font(SG.F.sans(14, .medium))
                .foregroundStyle(SG.C.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(.white, in: Capsule())
                .overlay(Capsule().stroke(SG.C.control, lineWidth: 1))
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ask.answer.see_all")
        }
    }

    private func citationCard(_ citation: Citation) -> some View {
        let index = citation.index
        let title = citation.opportunity.opportunityTitle ?? ""
        let meta = CitationMeta.text(for: citation.opportunity, locale: Locale.current)

        return Button {
            router.push(.opportunity(id: citation.opportunity.opportunityId), in: .search)
            router.tab = .search
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(verbatim: "\(index)")
                    .font(SG.F.sans(12, .semibold))
                    .foregroundStyle(SG.C.navy)
                    .frame(width: 22, height: 22)
                    .background(SG.C.navyTint, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title)
                        .font(SG.F.sans(15, .semibold))
                        .foregroundStyle(SG.C.ink)
                        .multilineTextAlignment(.leading)
                    if !meta.isEmpty {
                        Text(verbatim: meta)
                            .font(SG.F.sans(13))
                            .foregroundStyle(SG.C.muted)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                highlightedCitation == index ? SG.C.navyTint : SG.C.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(highlightedCitation == index ? SG.C.navy : SG.C.line, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                format: "ask.answer.source_label".localized(bundle: .module),
                index,
                title,
                meta
            )
        )
        .accessibilityHint("ask.answer.source_hint".localized(bundle: .module))
        .accessibilityIdentifier("ask.answer.citation.\(index)")
    }

    private var followupComposer: some View {
        HStack(spacing: 8) {
            TextField(
                "ask.answer.followup.placeholder".localized(bundle: .module),
                text: $followupText,
                axis: .vertical
            )
            .font(SG.F.sans(16))
            .foregroundStyle(SG.C.ink)
            .lineLimit(1...2)
            .focused($followupFocused)
            .accessibilityIdentifier("ask.followup.field")
            .onSubmit { sendFollowup() }
            .onChange(of: followupText) { _, newValue in
                guard newValue.contains("\n") || newValue.contains("\r") else { return }
                sendFollowup()
            }

            Button(action: sendFollowup) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AskComposer.normalized(followupText) == nil ? SG.C.subtle : .white)
                    .frame(width: 34, height: 34)
                    .background(
                        AskComposer.normalized(followupText) == nil ? SG.C.control : SG.C.navy,
                        in: Circle()
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(AskComposer.normalized(followupText) == nil)
            .accessibilityLabel("ask.answer.followup.send".localized(bundle: .module))
            .accessibilityIdentifier("ask.followup.send")
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .frame(minHeight: 46)
        .background(.white, in: Capsule())
        .overlay(Capsule().stroke(SG.C.line, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background {
            SG.C.canvas
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(SG.C.line)
                        .frame(height: 1)
                }
        }
    }

    private func sendFollowup() {
        guard let followup = AskComposer.normalized(followupText) else { return }
        recentQuestionsRaw = RecentQuestions.encode(
            RecentQuestions.adding(followup, to: RecentQuestions.decode(recentQuestionsRaw))
        )
        followupText = ""
        followupFocused = false
        router.push(.answer(question: followup), in: router.tab)
    }

    private func highlightCitation(_ index: Int) {
        highlightedCitation = index
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if highlightedCitation == index {
                highlightedCitation = nil
            }
        }
    }

    @MainActor
    private func loadAnswer() async {
        phase = .loading
        let composedQuestion = eligibility.engineQuestion(for: question)
        do {
            let answer = try await selectedEngine.answer(composedQuestion, removing: removedFilters)
            guard !Task.isCancelled else { return }
            phase = .loaded(answer)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }

    private var selectedEngine: any AskAnswering {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-SGAskPreviewEngine"),
                  arguments.indices.contains(index + 1) else {
                return engine
            }
            let mode: AskPreviewEngine.Mode
            switch arguments[index + 1] {
            case "answer": mode = .answer
            case "empty": mode = .empty
            case "failure": mode = .failure
            case "loading": mode = .loading
            default: return engine
            }
            return AskPreviewEngine(mode: mode)
        #else
            engine
        #endif
    }
}

private struct AnswerLoadKey: Equatable {
    let removedFilters: Set<InferredFilter>
    let reloadCounter: Int
}

private struct AnswerParagraphText: View {
    let paragraph: AnswerParagraph
    let citations: [Citation]
    let onShowSource: (Int) -> Void

    private var citationLookup: [Int: Citation] {
        Dictionary(uniqueKeysWithValues: citations.map { ($0.index, $0) })
    }

    private var attributedText: AttributedString {
        var result = AttributedString()
        let lookup = citationLookup
        for segment in paragraph.segments {
            var content = AttributedString(segment.text)
            if let index = segment.citationIndex,
               let opportunityTitle = lookup[index]?.opportunity.opportunityTitle {
                let name = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if index == 1,
                   opportunityTitle.localizedCaseInsensitiveHasPrefix(name),
                   !name.isEmpty {
                    content.font = SG.F.serif(17, .semibold)
                }
            }
            result.append(content)

            guard let index = segment.citationIndex, lookup[index] != nil else { continue }
            var superscript = AttributedString(" \(index)")
            superscript.font = SG.F.sans(11, .semibold)
            superscript.foregroundColor = SG.C.navy
            superscript.baselineOffset = 6
            superscript.link = URL(string: "sgcite://\(index)")
            result.append(superscript)
        }
        return result
    }

    private var citedIndexes: [Int] {
        let validIndexes = Set(citations.map(\.index))
        return Array(Set(paragraph.segments.compactMap(\.citationIndex).filter { validIndexes.contains($0) })).sorted()
    }

    private var spokenLabel: String {
        SpokenParagraph.text(for: paragraph, citations: citations)
    }

    var body: some View {
        var accessibleText = AnyView(
            Text(attributedText)
                .font(SG.F.answer)
                .foregroundColor(SG.C.body)
                .lineSpacing(5)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
        )
        for index in citedIndexes {
            let actionName = String(
                format: "ask.answer.show_source".localized(bundle: .module),
                index
            )
            accessibleText = AnyView(
                accessibleText.accessibilityAction(named: Text(verbatim: actionName)) {
                    onShowSource(index)
                }
            )
        }
        return accessibleText
    }
}

private struct LoadingAnswerView: View {
    @State private var tick = 0
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(SG.C.muted)
                            .frame(width: 6, height: 6)
                            .opacity(reduceMotion ? 0.8 : (tick % 3 == index ? 1 : 0.35))
                    }
                }
                Text(verbatim: "ask.answer.loading".localized(bundle: .module))
                    .font(SG.F.sans(15))
                    .foregroundStyle(SG.C.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("ask.answer.loading".localized(bundle: .module))

            VStack(alignment: .leading, spacing: 10) {
                skeleton(width: 0.94)
                skeleton(width: 0.82)
                skeleton(width: 0.9)
                skeleton(width: 0.56)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(1.5))
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    tick += 1
                }
            }
        }
    }

    private func skeleton(width: CGFloat) -> some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(SG.C.field)
                .frame(width: geometry.size.width * width, height: 10)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        return Self.measure(subviews: subviews, width: width, spacing: horizontalSpacing, rowSpacing: verticalSpacing)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private static func measure(
        subviews: Subviews,
        width: CGFloat,
        spacing: CGFloat,
        rowSpacing: CGFloat
    ) -> CGSize {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                maxWidth = max(maxWidth, x - spacing)
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        maxWidth = max(maxWidth, max(0, x - spacing))
        return CGSize(width: min(width, maxWidth), height: y + rowHeight)
    }
}

private extension String {
    func localizedCaseInsensitiveHasPrefix(_ prefix: String) -> Bool {
        guard let range = range(of: prefix, options: [.anchored, .caseInsensitive]) else {
            return false
        }
        return range.lowerBound == startIndex
    }
}

#Preview("Ask home") {
    AskHomeView()
        .environment(AppRouter())
        .environment(SessionStore(authenticator: PreviewAuthenticator()))
        .environment(\.askEngine, AskPreviewEngine())
}

#Preview("Ask with text") {
    AskHomeView(initialText: "A rural health clinic")
        .environment(AppRouter())
        .environment(SessionStore(authenticator: PreviewAuthenticator()))
}

#Preview("Answer") {
    AnswerView(question: "We run a rural clinic and want to expand addiction treatment")
        .environment(AppRouter())
        .environment(\.askEngine, AskPreviewEngine())
}

#Preview("Answer loading") {
    AnswerView(question: "We run a rural clinic")
        .environment(AppRouter())
        .environment(\.askEngine, AskPreviewEngine(mode: .loading))
}

#Preview("Answer empty") {
    AnswerView(question: "A question with no matching listings")
        .environment(AppRouter())
        .environment(\.askEngine, AskPreviewEngine(mode: .empty))
}

#Preview("Answer error") {
    AnswerView(question: "A question that cannot load")
        .environment(AppRouter())
        .environment(\.askEngine, AskPreviewEngine(mode: .failure))
}
