import SGModels

actor ApplyWarningsCache {
    static let shared = ApplyWarningsCache()
    private var warnings: [String: [ValidationWarning]] = [:]

    func set(_ value: [ValidationWarning], applicationId: String, formId: String) {
        warnings["\(applicationId)/\(formId)"] = value
    }

    func all(applicationId: String) -> [String: [ValidationWarning]] {
        warnings.reduce(into: [:]) { result, item in
            guard item.key.hasPrefix("\(applicationId)/") else { return }
            result[String(item.key.dropFirst(applicationId.count + 1))] = item.value
        }
    }
}
