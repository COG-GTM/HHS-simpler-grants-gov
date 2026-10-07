import SGModels

public struct FormModel: Sendable {
    public let sections: [FormSection]

    public init(definition: FormDefinition) throws {
        guard case .object = definition.formJsonSchema else {
            throw GrantsError.decoding("The form JSON schema must be an object.")
        }

        let rootProperties: [String: JSONValue]
        if case let .object(properties)? = definition.formJsonSchema["properties"] {
            rootProperties = properties
        } else {
            rootProperties = [:]
        }

        var builtSections: [FormSection] = []
        if case let .array(uiSections) = definition.formUiSchema {
            for (index, item) in uiSections.enumerated() {
                guard Self.string("type", in: item) == "section" else {
                    continue
                }
                let children: [JSONValue]
                if case let .array(values)? = item["children"] {
                    children = values
                } else {
                    children = []
                }
                let fields = children.compactMap { child -> FormField? in
                    guard
                        Self.string("type", in: child) == "field",
                        let path = Self.string("definition", in: child)
                    else {
                        return nil
                    }
                    let components = path.split(separator: "/").map(String.init)
                    let propertyIndex = components.firstIndex(of: "properties")
                    let propertyName: String
                    if let propertyIndex, components.indices.contains(propertyIndex + 1) {
                        propertyName = components[propertyIndex + 1]
                    } else if let last = components.last {
                        propertyName = last
                    } else {
                        return nil
                    }
                    let schema = rootProperties[propertyName] ?? .object([:])
                    let title = Self.string("title", in: schema)
                        ?? Self.string("label", in: child)
                        ?? propertyName
                    return FormField(path: path, title: title, schema: schema)
                }
                let sectionName = Self.string("name", in: item) ?? "section-\(index + 1)"
                let title = Self.string("label", in: item) ?? sectionName
                builtSections.append(FormSection(id: sectionName, title: title, fields: fields))
            }
        }

        if builtSections.isEmpty, !rootProperties.isEmpty {
            let fields = rootProperties.keys.sorted().map { propertyName in
                let schema = rootProperties[propertyName] ?? .object([:])
                return FormField(
                    path: "/properties/\(propertyName)",
                    title: Self.string("title", in: schema) ?? propertyName,
                    schema: schema
                )
            }
            builtSections.append(
                FormSection(
                    id: "application",
                    title: definition.shortFormName ?? definition.formName ?? "Application",
                    fields: fields
                )
            )
        }

        sections = builtSections
    }

    private static func string(_ key: String, in value: JSONValue) -> String? {
        guard case let .string(string)? = value[key] else {
            return nil
        }
        return string
    }
}

public struct FormSection: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let fields: [FormField]

    public init(id: String, title: String, fields: [FormField]) {
        self.id = id
        self.title = title
        self.fields = fields
    }
}

public struct FormField: Sendable, Hashable, Identifiable {
    public let path: String
    public let title: String
    public let schema: JSONValue

    public var id: String { path }

    public init(path: String, title: String, schema: JSONValue) {
        self.path = path
        self.title = title
        self.schema = schema
    }
}

public struct FieldError: Sendable, Hashable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public enum FormValidator {
    public static func validate(
        _ values: JSONValue,
        section: FormSection,
        model: FormModel
    ) -> [FieldError] {
        []
    }
}
