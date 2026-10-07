import SGAsk
import SGModels
import SwiftUI

private struct GrantsDataSourceKey: EnvironmentKey {
    static let defaultValue: any GrantsDataSource = PreviewDataSource()
}

private struct AskEngineKey: EnvironmentKey {
    static let defaultValue: any AskAnswering = AskEngine(dataSource: PreviewDataSource())
}

public extension EnvironmentValues {
    var grantsDataSource: any GrantsDataSource {
        get { self[GrantsDataSourceKey.self] }
        set { self[GrantsDataSourceKey.self] = newValue }
    }

    var askEngine: any AskAnswering {
        get { self[AskEngineKey.self] }
        set { self[AskEngineKey.self] = newValue }
    }
}
