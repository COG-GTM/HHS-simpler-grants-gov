import SGCore
import SGDesign
import SGModels
import SwiftUI

public struct ApplyHomeView: View {
    @Environment(\.grantsDataSource) private var dataSource
    @Environment(\.applyDraftStore) private var draftStore
    @Environment(\.applyProgressStore) private var progressStore
    @Environment(\.applyNow) private var now
    @Environment(AppRouter.self) private var router
    @State private var viewModel: WorkspaceViewModel?
    @State private var hasAppeared = false

    public init() {}

    public init(viewModel: WorkspaceViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            if let viewModel {
                switch viewModel.phase {
                case .loaded:
                    VStack(spacing: 0) {
                        Text("apply.home.title".localized(bundle: .module))
                            .font(ApplyTheme.F.serif(34))
                            .foregroundStyle(ApplyTheme.C.ink)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, ApplyTheme.S.margin)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                            .padding(.bottom, 10)
                        WorkspaceContent(
                            viewModel: viewModel,
                            applicationId: viewModel.loadedApplicationId ?? ""
                        )
                    }
                case .empty:
                    EmptyStateView(
                        title: "apply.home.empty_title".localized(bundle: .module),
                        message: "apply.home.empty_message".localized(bundle: .module),
                        actionTitle: "apply.home.search_action".localized(bundle: .module)
                    ) {
                        router.tab = .search
                    }
                    Spacer()
                case .failed(let message):
                    InlineErrorBanner(message: message) {
                        Task { await viewModel.load() }
                    }
                    .padding(20)
                    Spacer()
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ApplyTheme.C.canvas)
        .applyDataSourceEnvironment(dataSource)
        .toolbarHiddenForApply()
        .task {
            guard let viewModel else {
                let vm = WorkspaceViewModel(
                    applicationId: nil,
                    dataSource: ApplyDebugContext.dataSource(default: dataSource),
                    draftStore: draftStore,
                    progressStore: ApplyDebugContext.progressStore(default: progressStore),
                    now: now
                )
                self.viewModel = vm
                await vm.load()
                routeDebugLink(vm)
                return
            }
            if case .loading = viewModel.phase {
                await viewModel.load()
                routeDebugLink(viewModel)
            }
        }
        .onAppear {
            if hasAppeared {
                Task { await viewModel?.load() }
            }
            hasAppeared = true
        }
    }

    private func routeDebugLink(_ viewModel: WorkspaceViewModel) {
        #if DEBUG
        guard let route = ApplyDebugContext.consumeRoute(),
              let applicationId = viewModel.loadedApplicationId else {
            return
        }
        switch route {
        case "workspace":
            router.push(.application(id: applicationId))
        case "form":
            router.push(.application(id: applicationId))
            if let formId = viewModel.requiredRows.first?.id {
                router.push(.form(applicationId: applicationId, formId: formId))
            }
        case "review":
            router.push(.application(id: applicationId))
            router.push(.review(applicationId: applicationId))
        case "submitted":
            router.push(.submitted(applicationId: applicationId, trackingNumber: "GRANT14102837"))
        default:
            break
        }
        #endif
    }
}
