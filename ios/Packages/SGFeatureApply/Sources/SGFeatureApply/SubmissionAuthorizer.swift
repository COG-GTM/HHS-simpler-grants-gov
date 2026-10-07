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
            if let authenticationError = error as? LAError {
                switch authenticationError.code {
                case .biometryNotAvailable, .biometryNotEnrolled:
                    return .unavailable
                default:
                    break
                }
            }
            return .denied
        }
        #else
        return .unavailable
        #endif
    }
}
