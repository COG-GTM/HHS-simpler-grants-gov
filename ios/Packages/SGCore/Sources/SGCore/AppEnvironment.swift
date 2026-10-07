import Foundation

public struct AppEnvironment: Sendable {
    public enum DataMode: Sendable, Equatable {
        case sample
        case live(baseURL: URL)
    }

    public let dataMode: DataMode
    public let uiTestToken: String?
    public let deepLink: URL?

    public init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        userDefaults: UserDefaults = .standard
    ) {
        let mode = Self.argumentValue("-SGDataMode", in: arguments)?.lowercased()
        let token = Self.argumentValue("-SGUITestToken", in: arguments)
        uiTestToken = token?.isEmpty == false ? token : nil
        deepLink = Self.argumentValue("-SGDeepLink", in: arguments).flatMap(URL.init(string:))

        let selectedMode = mode ?? (userDefaults.string(forKey: "sg_data_mode")?.lowercased() ?? "sample")
        if selectedMode == "live" {
            dataMode = .live(baseURL: Self.localAPIBaseURL(
                from: Self.argumentValue("-SGAPIBaseURL", in: arguments)
            ))
        } else {
            dataMode = .sample
        }
    }

    private static func argumentValue(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func localAPIBaseURL(from value: String?) -> URL {
        let fallback = URL(string: "http://127.0.0.1:8080")!
        guard
            let value,
            let url = URL(string: value),
            url.scheme == "http",
            url.host == "127.0.0.1",
            url.port == 8080
        else {
            return fallback
        }
        return url
    }
}
