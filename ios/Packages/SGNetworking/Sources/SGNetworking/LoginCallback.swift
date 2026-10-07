import Foundation

public enum LoginCallbackResult: Sendable, Equatable {
    case success(token: String, isUserNew: Bool)
    case failure(description: String, pivRequired: Bool)
    case invalid
}

public enum LoginCallback {
    public static func parse(_ url: URL) -> LoginCallbackResult {
        guard
            url.scheme?.lowercased() == "simplergrants",
            url.host?.lowercased() == "auth",
            url.path == "/callback"
        else {
            return .invalid
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        let values = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, new in new })

        if values["message"] == "success" {
            guard let token = values["token"], !token.isEmpty else { return .invalid }
            return .success(token: token, isUserNew: values["is_user_new"] == "1")
        }
        guard values["message"] == "error" else { return .invalid }
        let description = values["error_description"] ?? "Sign in could not be completed."
        let pivRequired = values["login_piv_required_error"] != nil
            || description.localizedCaseInsensitiveContains("piv")
        return .failure(description: description, pivRequired: pivRequired)
    }
}
