import Foundation
import SGDesign
import SGModels

/// A form parsed from `FormDefinition.formJsonSchema` + `formUiSchema`.
///
/// Top-level UI-schema sections become `sections` (pages); `steps` groups
/// consecutive sections into the handful of steps the app shows with a
/// segmented progress bar.
public struct FormModel: Sendable {
    public let sections: [FormSection]
    public let steps: [FormStep]
    /// Fully resolved root JSON schema (`$ref`/`allOf` merged).
    public let schema: JSONValue
    public let formName: String?
    public let shortFormName: String?
    /// UI-schema `definition`s that did not resolve against the JSON schema.
    /// These render as "Finish on Simpler.Grants.gov" rows.
    public let unresolvedDefinitions: [String]

    let resolver: SchemaResolver

    public init(definition: FormDefinition) throws {
        guard case .object = definition.formJsonSchema else {
            throw GrantsError.decoding("The form JSON schema must be an object.")
        }
        let resolver = SchemaResolver(root: definition.formJsonSchema)
        var parser = UISchemaParser(resolver: resolver)
        var sections = parser.parseTopLevel(definition.formUiSchema)

        if sections.isEmpty {
            sections = [parser.fallbackSection(
                title: definition.formName ?? definition.shortFormName ?? "Application"
            )]
        }

        self.resolver = resolver
        self.schema = resolver.resolve(definition.formJsonSchema)
        self.sections = sections
        self.formName = definition.formName
        self.shortFormName = definition.shortFormName
        self.unresolvedDefinitions = parser.unresolved
        self.steps = FormStepPlanner.steps(for: sections, shortFormName: definition.shortFormName)
    }

    /// Every field in the form, in display order (FieldList children excluded).
    public var allFields: [FormField] {
        sections.flatMap(\.fields)
    }

    public func section(id: String) -> FormSection? {
        sections.first { $0.id == id }
    }

    /// The step containing `section`, if any.
    public func stepIndex(containing sectionID: String) -> Int? {
        steps.firstIndex { $0.sectionIDs.contains(sectionID) }
    }

    /// Supported vs "finish on web" field counts, for coverage reporting.
    public var coverage: FormCoverage {
        let inputs = allFields.filter { $0.kind != .heading && $0.kind != .staticText }
        return FormCoverage(
            supported: inputs.filter(\.isSupported).count,
            finishOnWeb: inputs.filter { !$0.isSupported }.count
        )
    }

    /// Progress against the validator: a step is complete when it has no errors
    /// and none of its fields have to be finished on the web.
    public func progress(values: JSONValue) -> FormProgress {
        let completed = steps.map { step in
            step.sections.allSatisfy {
                $0.isFullySupported && FormValidator.validate(values, section: $0, model: self).isEmpty
            }
        }
        let required = FormValidator.requiredStatus(values, model: self)
        return FormProgress(
            stepCompletion: completed,
            requiredAnswered: required.answered,
            requiredTotal: required.total
        )
    }
}

public struct FormSection: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let fields: [FormField]
    public let description: String?

    public init(id: String, title: String, fields: [FormField]) {
        self.init(id: id, title: title, fields: fields, description: nil)
    }

    public init(id: String, title: String, fields: [FormField], description: String?) {
        self.id = id
        self.title = title
        self.fields = fields
        self.description = description
    }

    /// `true` when every input in the section can be completed in the app.
    public var isFullySupported: Bool {
        fields.allSatisfy { $0.isSupported || $0.kind == .heading || $0.kind == .staticText }
    }
}

public struct FormStep: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let sectionIDs: [String]
    public let sections: [FormSection]

    public init(id: String, title: String, sections: [FormSection]) {
        self.id = id
        self.title = title
        self.sectionIDs = sections.map(\.id)
        self.sections = sections
    }

    public static func == (lhs: FormStep, rhs: FormStep) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.sectionIDs == rhs.sectionIDs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(sectionIDs)
    }
}

public struct FormProgress: Sendable, Hashable {
    /// One entry per `FormModel.steps`: `true` when that step validates and has
    /// no finish-on-web fields.
    public let stepCompletion: [Bool]
    public let requiredAnswered: Int
    public let requiredTotal: Int

    public var completedSteps: Int { stepCompletion.filter { $0 }.count }
    public var totalSteps: Int { stepCompletion.count }
    /// Index of the first incomplete step, or `nil` when all are complete.
    public var firstIncompleteStep: Int? { stepCompletion.firstIndex(of: false) }
    public var fraction: Double {
        requiredTotal == 0 ? (totalSteps == 0 ? 1 : Double(completedSteps) / Double(totalSteps))
            : Double(requiredAnswered) / Double(requiredTotal)
    }
    public var isComplete: Bool { stepCompletion.allSatisfy { $0 } }
}

public struct FormCoverage: Sendable, Hashable {
    public let supported: Int
    public let finishOnWeb: Int
}

public enum FieldKind: String, Sendable, Hashable, CaseIterable {
    case text
    case textArea
    case select
    case radio
    case checkbox
    case multiSelect
    case fieldList
    case table
    case attachment
    case attachmentArray
    /// A UI-schema `text` node: static content, no input.
    case staticText
    /// Visual heading for a nested UI-schema section.
    case heading
    /// Widgets the app doesn't render (e.g. SF-424A budget grids).
    case finishOnWeb
}

public enum TextFormat: String, Sendable, Hashable {
    case plain
    case email
    case date
    case phone
    case integer
    case number
    case currency
}

public struct FieldOption: Sendable, Hashable, Identifiable {
    public let value: JSONValue
    public let title: String
    public var id: String { title }

    public init(value: JSONValue, title: String) {
        self.value = value
        self.title = title
    }
}

public struct FormField: Sendable, Hashable, Identifiable {
    /// The UI-schema `definition` (JSON pointer into the JSON schema).
    public let path: String
    public let title: String
    /// The resolved, merged JSON schema for this field.
    public let schema: JSONValue
    public let id: String
    public let kind: FieldKind
    public let textFormat: TextFormat
    /// Where the value lives in `applicationResponse`. For FieldList children
    /// this is relative to one list entry.
    public let dataPath: FieldPath
    public let fieldDescription: String?
    /// Set for UI-schema `null` nodes and `readOnly` schemas (server-filled).
    public let isReadOnly: Bool
    public let options: [FieldOption]
    /// FieldList entry fields.
    public let children: [FormField]
    public let widget: String?
    /// All definitions for multiField nodes.
    public let definitions: [String]
    /// Static content for `text` nodes.
    public let content: String?
    public let minItems: Int?
    public let maxItems: Int?
    public let tableColumns: [String]

    public init(path: String, title: String, schema: JSONValue) {
        self.init(
            id: path,
            path: path,
            title: title,
            schema: schema,
            kind: FieldKindResolver.kind(widget: nil, schema: schema),
            dataPath: FieldPath(definition: path)
        )
    }

    public init(
        id: String,
        path: String,
        title: String,
        schema: JSONValue,
        kind: FieldKind,
        textFormat: TextFormat = .plain,
        dataPath: FieldPath,
        fieldDescription: String? = nil,
        isReadOnly: Bool = false,
        options: [FieldOption] = [],
        children: [FormField] = [],
        widget: String? = nil,
        definitions: [String] = [],
        content: String? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        tableColumns: [String] = []
    ) {
        self.id = id
        self.path = path
        self.title = title
        self.schema = schema
        self.kind = kind
        self.textFormat = textFormat
        self.dataPath = dataPath
        self.fieldDescription = fieldDescription
        self.isReadOnly = isReadOnly
        self.options = options
        self.children = children
        self.widget = widget
        self.definitions = definitions.isEmpty ? [path] : definitions
        self.content = content
        self.minItems = minItems
        self.maxItems = maxItems
        self.tableColumns = tableColumns
    }

    /// `false` for parts that must be finished on Simpler.Grants.gov.
    public var isSupported: Bool {
        kind != .finishOnWeb && kind != .table
    }

    /// Inputs the user can edit (not headings, static text or read-only values).
    public var isEditable: Bool {
        isSupported && !isReadOnly && kind != .heading && kind != .staticText
    }

    public var maxLength: Int? { schema.formInt("maxLength") }
}

enum FieldKindResolver {
    /// Mirrors `determineFieldType` in the web form, with an explicit
    /// UI-schema `widget` taking precedence.
    static func kind(widget: String?, schema: JSONValue) -> FieldKind {
        if let widget {
            switch widget {
            case "Text": return .text
            case "TextArea": return .textArea
            case "Select": return .select
            case "Radio": return .radio
            case "Checkbox": return .checkbox
            case "MultiSelect": return .multiSelect
            case "Attachment": return .attachment
            case "AttachmentArray": return .attachmentArray
            case "FieldList": return .fieldList
            case "Table": return .table
            default: return .finishOnWeb
            }
        }
        let type = schemaType(schema)
        if schema.formString("format") == "uuid" { return .attachment }
        if type == "array" {
            let items = schema.formObject?["items"] ?? .null
            if items.formString("format") == "uuid" { return .attachmentArray }
            if items.formObject?["enum"] != nil || items.formObject?["oneOf"] != nil { return .multiSelect }
            return .finishOnWeb
        }
        if schema.formObject?["enum"] != nil || hasConstOptions(schema) { return .select }
        if type == "boolean" { return .checkbox }
        if type == "object" { return .finishOnWeb }
        if let maxLength = schema.formInt("maxLength"), maxLength > 255 { return .textArea }
        return .text
    }

    static func schemaType(_ schema: JSONValue) -> String? {
        switch schema.formObject?["type"] {
        case let .string(type)?: return type
        case let .array(types)?: return types.compactMap(\.formString).first { $0 != "null" }
        default: return nil
        }
    }

    static func hasConstOptions(_ schema: JSONValue) -> Bool {
        let entries = schema.formObject?["oneOf"]?.formArray ?? schema.formObject?["anyOf"]?.formArray ?? []
        return !entries.isEmpty && entries.allSatisfy { $0.formObject?["const"] != nil }
    }

    static func options(for schema: JSONValue, kind: FieldKind) -> [FieldOption] {
        let source: JSONValue
        if kind == .multiSelect {
            source = schema.formObject?["items"] ?? .null
        } else {
            source = schema
        }
        if let values = source.formObject?["enum"]?.formArray {
            return values.map { FieldOption(value: $0, title: display($0)) }
        }
        let entries = source.formObject?["oneOf"]?.formArray ?? source.formObject?["anyOf"]?.formArray ?? []
        let constOptions = entries.compactMap { entry -> FieldOption? in
            guard let value = entry.formObject?["const"] else { return nil }
            return FieldOption(value: value, title: entry.formString("title") ?? display(value))
        }
        if !constOptions.isEmpty { return constOptions }
        if schemaType(source) == "boolean" {
            return [
                FieldOption(value: .bool(true), title: "forms.option.yes".localized(bundle: .module)),
                FieldOption(value: .bool(false), title: "forms.option.no".localized(bundle: .module))
            ]
        }
        return []
    }

    static func display(_ value: JSONValue) -> String {
        switch value {
        case let .string(string): return string
        case let .number(number):
            return number.rounded() == number ? String(Int(number)) : String(number)
        case let .bool(bool):
            return (bool ? "forms.option.yes" : "forms.option.no").localized(bundle: .module)
        default: return ""
        }
    }

    static func textFormat(schema: JSONValue, propertyName: String?) -> TextFormat {
        switch schema.formString("format") {
        case "email": return .email
        case "date": return .date
        default: break
        }
        switch schemaType(schema) {
        case "integer": return .integer
        case "number": return .number
        default: break
        }
        let name = (propertyName ?? "").lowercased()
        if name.contains("phone") || name == "fax" || name.hasSuffix("_fax") { return .phone }
        if let pattern = schema.formString("pattern"), pattern.contains("[.]\\d{2}") { return .currency }
        return .plain
    }
}
