import Foundation

public enum GrantsError: Error, Sendable, Equatable {
    case unauthorized
    case notFound
    case offline
    case server(status: Int, message: String?)
    case decoding(String)
}

extension GrantsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "You are not authorized to access this information."
        case .notFound:
            return "The requested item could not be found."
        case .offline:
            return "You appear to be offline."
        case let .server(_, message):
            return message ?? "The server could not complete the request."
        case let .decoding(message):
            return message
        }
    }
}
