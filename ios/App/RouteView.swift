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
        case let .results(request):
            ResultsView(request: request)
        case let .opportunity(id):
            OpportunityDetailView(opportunityId: id)
        case let .application(id):
            ApplicationWorkspaceView(applicationId: id)
        case let .form(applicationId, formId):
            FormScreenView(applicationId: applicationId, formId: formId)
        case let .review(applicationId):
            ReviewSubmitView(applicationId: applicationId)
        case let .submitted(applicationId, trackingNumber):
            SubmittedView(applicationId: applicationId, trackingNumber: trackingNumber)
        case .roadmap:
            RoadmapView()
        }
    }
}
