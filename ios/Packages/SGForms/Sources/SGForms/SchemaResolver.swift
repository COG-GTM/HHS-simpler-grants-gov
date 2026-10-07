import SGModels

/// Resolves JSON pointers into a form JSON schema, following local `$ref`s and
/// flattening `allOf` the same way the web form (`getFieldSchema`) and the API
/// registry do. Conditional `allOf` entries (`if`/`then`/`else`) are kept under
/// `allOf` so the validator can evaluate them against the data.
struct SchemaResolver {
    let root: JSONValue

    init(root: JSONValue) {
        self.root = root
    }

    /// Resolves a schema node: follows `$ref`, merges non-conditional `allOf`
    /// entries (outer keywords win), and keeps conditionals.
    func resolve(_ schema: JSONValue, depth: Int = 0) -> JSONValue {
        guard depth < 32, var object = schema.formObject else {
            return schema
        }

        var base: [String: JSONValue] = [:]
        if case let .string(ref)? = object.removeValue(forKey: "$ref"),
           let target = pointer(ref) {
            base = resolve(target, depth: depth + 1).formObject ?? [:]
        }

        var conditionals: [JSONValue] = []
        if case let .array(entries)? = object.removeValue(forKey: "allOf") {
            for entry in entries {
                let resolved = resolve(entry, depth: depth + 1)
                guard let entryObject = resolved.formObject else { continue }
                if entryObject["if"] != nil {
                    conditionals.append(resolved)
                } else {
                    base = Self.merge(base, entryObject)
                }
            }
        }

        var merged = Self.merge(base, object)
        if case let .array(inner)? = merged["allOf"] {
            conditionals = inner + conditionals
        }
        if conditionals.isEmpty {
            merged.removeValue(forKey: "allOf")
        } else {
            merged["allOf"] = .array(conditionals)
        }
        return .object(merged)
    }

    /// The resolved schema at a UI-schema `definition` such as
    /// `/properties/applicant/properties/street1` or
    /// `/properties/key_contacts/items/properties/name/properties/first_name`.
    func schema(at definition: String) -> JSONValue? {
        var current = resolve(root)
        for segment in Self.segments(of: definition) {
            guard let next = current.formObject?[segment] else { return nil }
            current = resolve(next)
        }
        return current
    }

    /// The resolved schema of every object along a definition, paired with the
    /// property name that leads to the next step. Used to compute `required`.
    func ancestry(of definition: String) -> [(parent: JSONValue, property: String)]? {
        let parts = Self.segments(of: definition)
        var result: [(JSONValue, String)] = []
        var current = resolve(root)
        var index = 0
        while index < parts.count {
            let keyword = parts[index]
            if keyword == "properties", index + 1 < parts.count {
                let name = parts[index + 1]
                result.append((current, name))
                guard let next = current.formObject?["properties"]?.formObject?[name] else { return nil }
                current = resolve(next)
                index += 2
            } else if keyword == "items" {
                guard let next = current.formObject?["items"] else { return nil }
                current = resolve(next)
                index += 1
            } else {
                guard let next = current.formObject?[keyword] else { return nil }
                current = resolve(next)
                index += 1
            }
        }
        return result
    }

    private func pointer(_ ref: String) -> JSONValue? {
        guard ref.hasPrefix("#") else { return nil }
        var current = root
        for segment in Self.segments(of: String(ref.dropFirst())) {
            if let object = current.formObject, let next = object[segment] {
                current = next
            } else if case let .array(items) = current, let index = Int(segment), items.indices.contains(index) {
                current = items[index]
            } else {
                return nil
            }
        }
        return current
    }

    static func segments(of pointer: String) -> [String] {
        pointer.split(separator: "/", omittingEmptySubsequences: true).map {
            $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
    }

    static func merge(_ lhs: [String: JSONValue], _ rhs: [String: JSONValue]) -> [String: JSONValue] {
        var result = lhs
        for (key, value) in rhs {
            switch (key, result[key], value) {
            case let ("properties", .object(old)?, .object(new)):
                result[key] = .object(old.merging(new) { existing, incoming in
                    .object(merge(existing.formObject ?? [:], incoming.formObject ?? [:]))
                })
            case let ("required", .array(old)?, .array(new)):
                result[key] = .array(old + new.filter { !old.contains($0) })
            case let ("allOf", .array(old)?, .array(new)):
                result[key] = .array(old + new)
            default:
                result[key] = value
            }
        }
        return result
    }
}

extension JSONValue {
    var formObject: [String: JSONValue]? {
        if case let .object(object) = self { return object }
        return nil
    }

    var formArray: [JSONValue]? {
        if case let .array(array) = self { return array }
        return nil
    }

    var formString: String? {
        if case let .string(string) = self { return string }
        return nil
    }

    var formNumber: Double? {
        if case let .number(number) = self { return number }
        return nil
    }

    var formBool: Bool? {
        if case let .bool(bool) = self { return bool }
        return nil
    }

    func formString(_ key: String) -> String? { formObject?[key]?.formString }
    func formNumber(_ key: String) -> Double? { formObject?[key]?.formNumber }
    func formInt(_ key: String) -> Int? { formNumber(key).map { Int($0) } }
    func formStrings(_ key: String) -> [String] { formObject?[key]?.formArray?.compactMap(\.formString) ?? [] }

    /// `true` for values the web form treats as "not answered".
    var isFormBlank: Bool {
        switch self {
        case .null: return true
        case let .string(string): return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .array(array): return array.isEmpty
        case let .object(object): return object.values.allSatisfy(\.isFormBlank)
        case .bool, .number: return false
        }
    }
}
