import SGCore
import SwiftUI

@_spi(Snapshots)
public struct ApplySnapshotHost<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .environment(AppRouter(tab: .apply))
            .environment(\.applyDraftStore, InMemoryApplyDraftStore())
            .environment(\.applyProgressStore, InMemoryFormProgressStore())
    }
}
