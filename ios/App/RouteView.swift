import SGCore
import SGFeatureApply
import SGFeatureAsk
import SGFeatureProfile
import SGFeatureSearch
import SwiftUI

struct RouteView: View {
    let route: AppRoute

    @ViewBuilder
    var body: some View {
        switch route {
        case let .answer(question):
            AnswerView(question: question)
                .toolbar(.hidden, for: .tabBar)
        case let .results(request):
            ResultsView(request: request)
        case let .opportunity(id):
            OpportunityDetailView(opportunityId: id)
                .toolbar(.hidden, for: .tabBar)
        case let .application(id):
            ApplicationWorkspaceView(applicationId: id)
        case let .form(applicationId, formId):
            FormScreenView(applicationId: applicationId, formId: formId)
                .toolbar(.hidden, for: .tabBar)
        case let .review(applicationId):
            ReviewSubmitView(applicationId: applicationId)
                .toolbar(.hidden, for: .tabBar)
        case let .submitted(applicationId, trackingNumber):
            SubmittedView(applicationId: applicationId, trackingNumber: trackingNumber)
                .toolbar(.hidden, for: .tabBar)
        case .roadmap:
            RoadmapView()
                .toolbar(.hidden, for: .tabBar)
        }
    }
}
