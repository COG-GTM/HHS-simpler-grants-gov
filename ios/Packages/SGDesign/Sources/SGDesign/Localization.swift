import Foundation

public extension String {
    func localized(bundle: Bundle = .main) -> String {
        NSLocalizedString(self, bundle: bundle, comment: "")
    }
}
