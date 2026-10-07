import SGCore
import SwiftUI

private struct ApplyProgressStoreKey: EnvironmentKey {
    static let defaultValue: any FormProgressStore = UserDefaultsFormProgressStore()
}

private struct ApplyAttachmentStoreKey: EnvironmentKey {
    static let defaultValue: any ApplyAttachmentStore = FileApplyAttachmentStore()
}

private struct ApplyNowKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Date = { Date() }
}

private struct ApplySubmissionAuthorizerKey: EnvironmentKey {
    static let defaultValue: any SubmissionAuthorizing = LocalAuthenticationAuthorizer()
}

public extension EnvironmentValues {
    var applyDraftStore: any DraftStore {
        get { self.draftStore }
        set { self.draftStore = newValue }
    }

    var applyProgressStore: any FormProgressStore {
        get { self[ApplyProgressStoreKey.self] }
        set { self[ApplyProgressStoreKey.self] = newValue }
    }

    var applyAttachmentStore: any ApplyAttachmentStore {
        get { self[ApplyAttachmentStoreKey.self] }
        set { self[ApplyAttachmentStoreKey.self] = newValue }
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
