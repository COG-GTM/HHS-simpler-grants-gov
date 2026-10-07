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
                Text("apply.coming_soon".localized(bundle: .module))
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

public struct ApplyHomeView: View {
    public init() {}

    public var body: some View {
        FeatureStubScreen(titleKey: "apply.home.title")
    }
}

public struct ApplicationWorkspaceView: View {
    private let applicationId: String

    public init(applicationId: String) {
        self.applicationId = applicationId
    }

    public var body: some View {
        FeatureStubScreen(titleKey: "apply.workspace.title")
    }
}

public struct FormScreenView: View {
    private let applicationId: String
    private let formId: String

    public init(applicationId: String, formId: String) {
        self.applicationId = applicationId
        self.formId = formId
    }

    public var body: some View {
        FeatureStubScreen(titleKey: "apply.form.title")
    }
}

public struct ReviewSubmitView: View {
    private let applicationId: String

    public init(applicationId: String) {
        self.applicationId = applicationId
    }

    public var body: some View {
        FeatureStubScreen(titleKey: "apply.review.title")
    }
}

public struct SubmittedView: View {
    private let applicationId: String
    private let trackingNumber: String?

    public init(applicationId: String, trackingNumber: String?) {
        self.applicationId = applicationId
        self.trackingNumber = trackingNumber
    }

    public var body: some View {
        FeatureStubScreen(titleKey: "apply.submitted.title")
    }
}

#Preview("Apply home") {
    ApplyHomeView()
}

#Preview("Application workspace") {
    ApplicationWorkspaceView(applicationId: "sample")
}

#Preview("Form") {
    FormScreenView(applicationId: "sample", formId: "sample")
}

#Preview("Review") {
    ReviewSubmitView(applicationId: "sample")
}

#Preview("Submitted") {
    SubmittedView(applicationId: "sample", trackingNumber: "SAMPLE-0001")
}
