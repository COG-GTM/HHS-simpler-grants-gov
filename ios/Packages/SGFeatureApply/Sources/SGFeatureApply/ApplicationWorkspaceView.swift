import SGCore
import SGDesign
import SGModels
import SwiftUI

public struct ApplicationWorkspaceView: View {
    private let applicationId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.grantsDataSource) private var dataSource
    @Environment(\.applyDraftStore) private var draftStore
    @Environment(\.applyProgressStore) private var progressStore
    @Environment(\.applyNow) private var now
    @State private var viewModel: WorkspaceViewModel?
    @State private var hasAppeared = false

    public init(applicationId: String) {
        self.applicationId = applicationId
    }

    public init(viewModel: WorkspaceViewModel) {
        applicationId = viewModel.applicationId ?? ""
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            DemoBanner()
            SGNavBar(
                backLabel: "apply.workspace.back".localized(bundle: .module),
                title: "apply.workspace.nav_title".localized(bundle: .module),
                onBack: nil
            )
            .padding(.horizontal, 12)

            if let viewModel {
                switch viewModel.phase {
                case .loaded:
                    WorkspaceContent(viewModel: viewModel, applicationId: applicationId)
                case .failed(let message):
                    InlineErrorBanner(message: message) {
                        Task { await viewModel.load() }
                    }
                    .padding(20)
                    Spacer()
                case .loading, .empty:
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
                    applicationId: applicationId,
                    dataSource: ApplyDebugContext.dataSource(default: dataSource),
                    draftStore: draftStore,
                    progressStore: ApplyDebugContext.progressStore(default: progressStore),
                    now: now
                )
                self.viewModel = vm
                await vm.load()
                return
            }
            if case .loading = viewModel.phase {
                await viewModel.load()
            }
        }
        .onAppear {
            if hasAppeared {
                Task { await viewModel?.load() }
            }
            hasAppeared = true
        }
    }
}

extension View {
    func toolbarHiddenForApply(hideTabBar: Bool = false) -> some View {
        #if os(iOS)
        modifier(ApplyToolbarVisibilityModifier(hideTabBar: hideTabBar))
        #else
        self
        #endif
    }

    func applyDataSourceEnvironment(_ source: any GrantsDataSource) -> some View {
        #if DEBUG
        environment(\.grantsDataSource, ApplyDebugContext.dataSource(default: source))
        #else
        environment(\.grantsDataSource, source)
        #endif
    }
}

#if os(iOS)
private struct ApplyToolbarVisibilityModifier: ViewModifier {
    let hideTabBar: Bool

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(hideTabBar ? .hidden : .visible, for: .tabBar)
    }
}
#endif
