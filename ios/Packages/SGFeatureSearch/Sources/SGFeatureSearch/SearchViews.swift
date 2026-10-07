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
                Text("search.coming_soon".localized(bundle: .module))
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

public struct SearchHomeView: View {
    public init() {}

    public var body: some View {
        FeatureStubScreen(titleKey: "search.home.title")
    }
}

public struct ResultsView: View {
    private let request: SearchRequest

    public init(request: SearchRequest) {
        self.request = request
    }

    public var body: some View {
        FeatureStubScreen(titleKey: "search.results.title")
    }
}

public struct FiltersSheet: View {
    @Binding private var filters: SearchFilters

    public init(filters: Binding<SearchFilters>) {
        _filters = filters
    }

    public var body: some View {
        FeatureStubScreen(titleKey: "search.filters.title")
    }
}

public struct OpportunityDetailView: View {
    private let opportunityId: String

    public init(opportunityId: String) {
        self.opportunityId = opportunityId
    }

    public var body: some View {
        FeatureStubScreen(titleKey: "search.detail.title")
    }
}

#Preview("Search home") {
    SearchHomeView()
}

#Preview("Results") {
    ResultsView(request: SearchRequest())
}

#Preview("Filters") {
    FiltersSheet(filters: .constant(SearchFilters()))
}

#Preview("Opportunity detail") {
    OpportunityDetailView(opportunityId: "sample")
}
