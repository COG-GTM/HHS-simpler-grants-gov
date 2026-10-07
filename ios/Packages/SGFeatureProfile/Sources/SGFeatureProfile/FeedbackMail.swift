import Foundation

public enum FeedbackMail {
    public static let recipient = "feedback@example.org"

    public static func url(message: String) -> URL? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Simpler.Grants.gov demo feedback"),
            URLQueryItem(name: "body", value: trimmedMessage)
        ]
        return components.url
    }
}
