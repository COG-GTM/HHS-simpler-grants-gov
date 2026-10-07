import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

public enum SubmissionAuthorization: Sendable {
    case authorized
    case unavailable
    case denied
}

public protocol SubmissionAuthorizing: Sendable {
    func authorize(reason: String) async -> SubmissionAuthorization
}

public struct LocalAuthenticationAuthorizer: SubmissionAuthorizing {
    public init() {}

    public func authorize(reason: String) async -> SubmissionAuthorization {
        #if canImport(LocalAuthentication)
        guard Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") != nil else {
            return .unavailable
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .unavailable
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success ? .authorized : .denied
        } catch {
            guard let authenticationError = error as? LAError else { return .unavailable }
            switch authenticationError.code {
            case .userCancel, .userFallback, .authenticationFailed:
                return .denied
            default:
                return .unavailable
            }
        }
        #else
        return .unavailable
        #endif
    }
}
