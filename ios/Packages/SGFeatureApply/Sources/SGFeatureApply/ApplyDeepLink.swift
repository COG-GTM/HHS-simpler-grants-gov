import Foundation
import SGCore
import SGModels

@MainActor
enum ApplyDebugContext {
#if DEBUG
    private static var handledRoute = false
    private static var referenceScenario: ApplyReferenceDataSource.Scenario?
    private static var referenceDataSource: ApplyReferenceDataSource?
    private static var referenceProgress: InMemoryFormProgressStore?
#endif

    static func dataSource(default source: any GrantsDataSource) -> any GrantsDataSource {
#if DEBUG
        guard let scenario = fixtureScenario() else { return source }
        if referenceScenario != scenario {
            referenceScenario = scenario
            referenceDataSource = ApplyReferenceDataSource(scenario: scenario)
            referenceProgress = ApplyReferenceDataSource.progressStore(for: scenario)
        }
        return referenceDataSource ?? source
#else
        source
#endif
    }

    static func progressStore(default store: any FormProgressStore) -> any FormProgressStore {
#if DEBUG
        guard fixtureScenario() != nil else { return store }
        _ = dataSource(default: PreviewDataSource())
        return referenceProgress ?? store
#else
        store
#endif
    }

    static func consumeRoute() -> String? {
#if DEBUG
        guard !handledRoute else { return nil }
        handledRoute = true
        return argumentValue("-SGApplyRoute")
#else
        nil
#endif
    }

#if DEBUG
    private static func fixtureScenario() -> ApplyReferenceDataSource.Scenario? {
        switch argumentValue("-SGApplyFixture") {
        case "inProgress": return .inProgress
        case "allComplete": return .allComplete
        case "empty": return .empty
        default: return nil
        }
    }

    private static func argumentValue(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
#endif
}
