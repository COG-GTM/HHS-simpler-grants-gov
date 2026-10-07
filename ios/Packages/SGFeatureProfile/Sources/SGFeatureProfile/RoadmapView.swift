import SGDesign
import SwiftUI

public struct RoadmapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    private let content: RoadmapContent
    private let initialScrollTarget: String?
    @State private var voteStore: RoadmapVoteStore
    @State private var feedbackMessage = ""
    @State private var feedbackOpened: Bool?

    public init() {
        self.init(
            content: (try? RoadmapContent.loadBundled()) ?? RoadmapContent(sections: []),
            voteStore: RoadmapVoteStore(),
            initialScrollTarget: nil
        )
    }

    public init(content: RoadmapContent, voteStore: RoadmapVoteStore) {
        self.init(content: content, voteStore: voteStore, initialScrollTarget: nil)
    }

    init(
        content: RoadmapContent,
        voteStore: RoadmapVoteStore,
        initialScrollTarget: String?
    ) {
        self.content = content
        self.initialScrollTarget = initialScrollTarget
        _voteStore = State(initialValue: voteStore)
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            SGNavBar(
                backLabel: "roadmap.back".localized(bundle: .module),
                title: "",
                onBack: { dismiss() }
            )
            .padding(.horizontal, SG.S.margin)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: SG.S.xl) {
                        VStack(alignment: .leading, spacing: SG.S.s) {
                            Text("roadmap.title".localized(bundle: .module))
                                .font(SG.F.largeTitle)
                                .foregroundStyle(SG.C.ink)
                                .accessibilityAddTraits(.isHeader)
                            Text("roadmap.intro".localized(bundle: .module))
                                .font(SG.F.bodyText)
                                .foregroundStyle(SG.C.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("roadmap.vote.caption".localized(bundle: .module))
                                .font(SG.F.caption)
                                .foregroundStyle(SG.C.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ForEach(content.sections) { section in
                            VStack(alignment: .leading, spacing: SG.S.m) {
                                Text(section.title)
                                    .font(SG.F.section)
                                    .foregroundStyle(SG.C.ink)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityIdentifier("roadmap.section.\(section.id)")
                                ForEach(section.items) { item in
                                    roadmapCard(item)
                                }
                            }
                        }

                        feedbackSection
                    }
                    .padding(.horizontal, SG.S.margin)
                    .padding(.top, SG.S.s)
                    .padding(.bottom, SG.S.xl)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onAppear {
                    guard let initialScrollTarget else { return }
                    proxy.scrollTo(initialScrollTarget, anchor: .top)
                }
            }
        }
        .background(SG.C.canvas.ignoresSafeArea())
        .sgHideNavigationBar()
        .sgHideTabBar()
        .accessibilityIdentifier("roadmap.screen")
    }

    private func roadmapCard(_ item: RoadmapItem) -> some View {
        Card {
            HStack(alignment: .top, spacing: SG.S.m) {
                VStack(alignment: .leading, spacing: SG.S.s) {
                    Text(item.status.localizationKey.localized(bundle: .module))
                        .font(SG.F.sans(12, .semibold))
                        .foregroundStyle(item.status.foregroundColor)
                        .padding(.horizontal, SG.S.s)
                        .padding(.vertical, SG.S.xs)
                        .background(item.status.backgroundColor, in: Capsule())
                    Text(item.title)
                        .font(SG.F.sans(15, .semibold))
                        .foregroundStyle(SG.C.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(SG.F.sans(13))
                            .foregroundStyle(SG.C.muted)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                voteControl(for: item)
            }
        }
        .id(item.id)
        .accessibilityIdentifier("roadmap.item.\(item.id)")
    }

    @ViewBuilder
    private func voteControl(for item: RoadmapItem) -> some View {
        if let count = voteStore.count(for: item) {
            Button {
                voteStore.toggle(item.id)
            } label: {
                voteBox(voted: voteStore.hasVoted(item.id)) {
                    VStack(spacing: SG.S.xs) {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(SG.F.sans(11, .semibold))
                            .accessibilityHidden(true)
                        voteCount(count)
                    }
                    .foregroundStyle(SG.C.navy)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(
                format: (voteStore.hasVoted(item.id)
                    ? "roadmap.vote.accessibility.remove"
                    : "roadmap.vote.accessibility.upvote").localized(bundle: .module),
                locale: Locale(identifier: "en_US"),
                count
            ))
            .accessibilityIdentifier("roadmap.vote.\(item.id)")
        } else {
            voteBox(voted: false) {
                Text("roadmap.vote.released".localized(bundle: .module))
                    .font(SG.F.sans(15, .semibold))
                    .foregroundStyle(SG.C.subtle)
                    .lineLimit(1)
                    .fixedSize()
                    .monospacedDigit()
            }
                .accessibilityLabel("roadmap.vote.released_accessibility".localized(bundle: .module))
                .accessibilityIdentifier("roadmap.vote.\(item.id)")
        }
    }

    private func voteBox<Content: View>(
        voted: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, SG.S.s)
            .frame(minWidth: 52, minHeight: 52)
            .background(
                voted ? SG.C.navyTint : SG.C.surface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(voted ? SG.C.navy : SG.C.control, lineWidth: voted ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func voteCount(_ count: Int) -> some View {
        let text = Text(count, format: .number)
            .font(SG.F.sans(15, .semibold))
            .lineLimit(1)
            .fixedSize()
        if dynamicTypeSize.isAccessibilitySize {
            text.monospacedDigit()
        } else {
            text
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: SG.S.m) {
            Text("roadmap.feedback.heading".localized(bundle: .module))
                .font(SG.F.section)
                .foregroundStyle(SG.C.ink)
                .accessibilityAddTraits(.isHeader)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: SG.R.input, style: .continuous)
                    .fill(SG.C.surface)
                RoundedRectangle(cornerRadius: SG.R.input, style: .continuous)
                    .stroke(SG.C.line, lineWidth: 1)
                if feedbackMessage.isEmpty {
                    Text("roadmap.feedback.placeholder".localized(bundle: .module))
                        .font(SG.F.bodyText)
                        .foregroundStyle(SG.C.subtle)
                        .padding(.horizontal, SG.S.m)
                        .padding(.top, SG.S.m)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $feedbackMessage)
                    .font(SG.F.bodyText)
                    .scrollContentBackground(.hidden)
                    .padding(SG.S.xs)
                    .accessibilityLabel("roadmap.feedback.placeholder".localized(bundle: .module))
                    .accessibilityIdentifier("roadmap.feedback.message")
            }
            .frame(minHeight: 132)

            Button(action: sendFeedback) {
                Text("roadmap.feedback.send".localized(bundle: .module))
            }
            .buttonStyle(PrimaryButton(enabled: !feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            .disabled(feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("roadmap.feedback.send")

            if let feedbackOpened {
                Text(
                    (feedbackOpened
                        ? "roadmap.feedback.body.accepted"
                        : "roadmap.feedback.body.unavailable").localized(bundle: .module)
                )
                .font(SG.F.caption)
                .foregroundStyle(SG.C.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("roadmap.feedback.result")
            }
        }
    }

    private func sendFeedback() {
        guard let url = FeedbackMail.url(message: feedbackMessage) else { return }
        openURL(url) { accepted in
            feedbackOpened = accepted
        }
    }
}

private extension RoadmapItemStatus {
    var foregroundColor: Color {
        switch self {
        case .inProgress: SG.C.navy
        case .planned: SG.C.foreFg
        case .released: SG.C.openFg
        }
    }

    var backgroundColor: Color {
        switch self {
        case .inProgress: SG.C.navyTint
        case .planned: SG.C.foreBg
        case .released: SG.C.openBg
        }
    }
}
