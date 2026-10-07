import SGDesign
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
                Text("profile.coming_soon".localized(bundle: .module))
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

public struct ProfileView: View {
    public init() {}

    public var body: some View {
        FeatureStubScreen(titleKey: "profile.home.title")
    }
}

public struct RoadmapView: View {
    public init() {}

    public var body: some View {
        FeatureStubScreen(titleKey: "profile.roadmap.title")
    }
}

#Preview("Profile") {
    ProfileView()
}

#Preview("Roadmap") {
    RoadmapView()
}
