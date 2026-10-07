import SGDesign
import SGModels
import SwiftUI

private struct FeatureStubScreen: View {
    let titleKey: String

    var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            VStack(spacing: 16) {
                Text(titleKey.localized(bundle: .module))
                    .font(.largeTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("ask.coming_soon".localized(bundle: .module))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }
}

public struct AskHomeView: View {
    public init() {}

    public var body: some View {
        FeatureStubScreen(titleKey: "ask.home.title")
    }
}

public struct AnswerView: View {
    private let question: String

    public init(question: String) {
        self.question = question
    }

    public var body: some View {
        FeatureStubScreen(titleKey: "ask.answer.title")
    }
}

#Preview("Ask home") {
    AskHomeView()
}

#Preview("Answer") {
    AnswerView(question: "Sample question")
}
