import SGCore
import SwiftUI

private struct ApplyDraftStoreKey: EnvironmentKey {
    static let defaultValue: any DraftStore = FileDraftStore()
}

private struct ApplyProgressStoreKey: EnvironmentKey {
    static let defaultValue: any FormProgressStore = UserDefaultsFormProgressStore()
}

private struct ApplyNowKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Date = { Date() }
}

private struct ApplySubmissionAuthorizerKey: EnvironmentKey {
    static let defaultValue: any SubmissionAuthorizing = LocalAuthenticationAuthorizer()
}

public extension EnvironmentValues {
    var applyDraftStore: any DraftStore {
        get { self[ApplyDraftStoreKey.self] }
        set { self[ApplyDraftStoreKey.self] = newValue }
    }

    var applyProgressStore: any FormProgressStore {
        get { self[ApplyProgressStoreKey.self] }
        set { self[ApplyProgressStoreKey.self] = newValue }
    }

    var applyNow: @Sendable () -> Date {
        get { self[ApplyNowKey.self] }
        set { self[ApplyNowKey.self] = newValue }
    }

    var applySubmissionAuthorizer: any SubmissionAuthorizing {
        get { self[ApplySubmissionAuthorizerKey.self] }
        set { self[ApplySubmissionAuthorizerKey.self] = newValue }
    }
}
