import Foundation
import SGDesign
import SGModels

public struct FieldError: Sendable, Hashable {
    /// JSON path of the invalid value, e.g. `$.email` or `$.key_contacts[0].title`.
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// Validates an application response against the form's JSON schema, scoped
/// to the fields of one section. Call it when the user taps "Save and continue".
public enum FormValidator {
    public static func validate(
        _ values: JSONValue,
        section: FormSection,
        model: FormModel
    ) -> [FieldError] {
        var errors: [FieldError] = []
        for field in section.fields {
            validate(field, at: field.dataPath, indexes: [], values: values, model: model, into: &errors)
        }
        return deduplicated(errors)
    }

    /// Validates every section in a step.
    public static func validate(_ values: JSONValue, step: FormStep, model: FormModel) -> [FieldError] {
        deduplicated(step.sections.flatMap { validate(values, section: $0, model: model) })
    }

    /// Validates the whole form.
    public static func validate(_ values: JSONValue, model: FormModel) -> [FieldError] {
        deduplicated(model.sections.flatMap { validate(values, section: $0, model: model) })
    }

    /// Whether `field` is required given the current answers (including
    /// conditional `if`/`then` rules).
    public static func isRequired(_ field: FormField, in values: JSONValue, model: FormModel) -> Bool {
        isRequired(definition: field.path, dataPath: field.dataPath, values: values, model: model)
    }

    static func requiredStatus(_ values: JSONValue, model: FormModel) -> (answered: Int, total: Int) {
        var answered = 0
        var total = 0
        for field in model.allFields where field.isEditable && field.kind != .fieldList {
            guard isRequired(field, in: values, model: model) else { continue }
            total += 1
            if !(values.value(at: field.dataPath)?.isFormBlank ?? true) { answered += 1 }
        }
        return (answered, total)
    }

    // MARK: - Field checks

    private static func validate(
        _ field: FormField,
        at path: FieldPath,
        indexes: [Int],
        values: JSONValue,
        model: FormModel,
        into errors: inout [FieldError]
    ) {
        guard field.isSupported, field.kind != .heading, field.kind != .staticText else { return }
        let value = values.value(at: path)

        if field.kind == .fieldList {
            let items = value?.formArray ?? []
            let count = items.count
            if let minItems = field.minItems, count < minItems,
               isRequired(definition: field.path, dataPath: path, values: values, model: model) || count > 0 {
                errors.append(FieldError(path: path.jsonPath, message: message(.minItems(minItems), field)))
            }
            if let maxItems = field.maxItems, count > maxItems {
                errors.append(FieldError(path: path.jsonPath, message: message(.maxItems(maxItems), field)))
            }
            let entryCount = max(count, field.minItems ?? 0)
            for index in 0..<entryCount {
                for child in field.children {
                    validate(
                        child,
                        at: path.appending(index: index).appending(child.dataPath),
                        indexes: indexes + [index],
                        values: values,
                        model: model,
                        into: &errors
                    )
                }
            }
            return
        }

        // Read-only values are filled by the server; never block the user on them.
        if field.isReadOnly { return }

        guard let value, !value.isFormBlank else {
            if isRequired(definition: field.path, dataPath: path, values: values, model: model) {
                errors.append(FieldError(path: path.jsonPath, message: message(.required, field)))
            }
            return
        }

        if let problem = check(value, against: field.schema, field: field) {
            errors.append(FieldError(path: path.jsonPath, message: message(problem, field)))
        }
    }

    enum Problem: Equatable {
        case required
        case email
        case date
        case type(String)
        case option
        case pattern
        case minLength(Int)
        case maxLength(Int)
        case exactLength(Int)
        case minimum(Double)
        case maximum(Double)
        case minItems(Int)
        case maxItems(Int)
    }

    /// First problem with a present, non-blank value.
    static func check(_ value: JSONValue, against schema: JSONValue, field: FormField?) -> Problem? {
        let type = FieldKindResolver.schemaType(schema)

        if let type, !matchesType(value, type) {
            if (type == "number" || type == "integer"), case let .string(text) = value,
               let number = Double(text.trimmingCharacters(in: .whitespaces)) {
                return check(.number(number), against: schema, field: field)
            }
            return .type(type)
        }

        if case let .array(items) = value {
            if let minItems = schema.formInt("minItems"), items.count < minItems { return .minItems(minItems) }
            if let maxItems = schema.formInt("maxItems"), items.count > maxItems { return .maxItems(maxItems) }
            if let itemSchema = schema.formObject?["items"] {
                for item in items where !item.isFormBlank {
                    if let problem = check(item, against: itemSchema, field: nil) { return problem }
                }
            }
            return nil
        }

        if let allowed = allowedValues(schema), !allowed.contains(value) {
            return .option
        }

        if case let .string(text) = value {
            switch schema.formString("format") {
            case "email" where !isEmail(text): return .email
            case "date" where !isDate(text): return .date
            default: break
            }
            let length = text.count
            let minLength = schema.formInt("minLength")
            let maxLength = schema.formInt("maxLength")
            if let minLength, let maxLength, minLength == maxLength, length != minLength {
                return .exactLength(minLength)
            }
            if let minLength, length < minLength { return .minLength(minLength) }
            if let maxLength, length > maxLength { return .maxLength(maxLength) }
            if let pattern = schema.formString("pattern"), !matches(text, pattern: pattern) {
                return .pattern
            }
        }

        if case let .number(number) = value {
            if let minimum = schema.formNumber("minimum"), number < minimum { return .minimum(minimum) }
            if let maximum = schema.formNumber("maximum"), number > maximum { return .maximum(maximum) }
            if let minimum = schema.formNumber("exclusiveMinimum"), number <= minimum { return .minimum(minimum) }
            if let maximum = schema.formNumber("exclusiveMaximum"), number >= maximum { return .maximum(maximum) }
        }
        return nil
    }

    private static func allowedValues(_ schema: JSONValue) -> [JSONValue]? {
        if let values = schema.formObject?["enum"]?.formArray { return values }
        if let constant = schema.formObject?["const"] { return [constant] }
        if FieldKindResolver.hasConstOptions(schema) {
            let entries = schema.formObject?["oneOf"]?.formArray ?? schema.formObject?["anyOf"]?.formArray ?? []
            return entries.compactMap { $0.formObject?["const"] }
        }
        return nil
    }

    static func matchesType(_ value: JSONValue, _ type: String) -> Bool {
        switch (type, value) {
        case ("string", .string), ("boolean", .bool), ("array", .array), ("object", .object), ("null", .null):
            return true
        case ("number", .number):
            return true
        case let ("integer", .number(number)):
            return number.rounded() == number
        default:
            return false
        }
    }

    static func isEmail(_ text: String) -> Bool {
        matches(text, pattern: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}$"#)
    }

    static func isDate(_ text: String) -> Bool {
        guard matches(text, pattern: #"^\d{4}-\d{2}-\d{2}$"#) else { return false }
        return FormDateFormat.date(from: text) != nil
    }

    static func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - Required, including conditionals

    static func isRequired(definition: String, dataPath: FieldPath, values: JSONValue, model: FormModel) -> Bool {
        guard let ancestry = model.resolver.ancestry(of: definition), !ancestry.isEmpty else { return false }
        // Pair each `properties` step with the concrete parent data path.
        var parentPath = FieldPath()
        var keyIterator = dataPath.components.makeIterator()
        for (offset, step) in ancestry.enumerated() {
            // Advance through index components to the next key.
            var component = keyIterator.next()
            while case .index? = component {
                parentPath = FieldPath(parentPath.components + [component!])
                component = keyIterator.next()
            }
            let parentData = values.value(at: parentPath) ?? .object([:])
            let required = effectiveRequired(step.parent, data: parentData)
            let isLast = offset == ancestry.count - 1
            let childPath = FieldPath(parentPath.components + [.key(step.property)])
            if isLast {
                return required.contains(step.property)
            }
            let childPresent = !(values.value(at: childPath)?.isFormBlank ?? true)
            if !required.contains(step.property) && !childPresent {
                return false
            }
            parentPath = childPath
        }
        return false
    }

    /// `required` plus the `required` of every conditional whose `if` matches.
    static func effectiveRequired(_ schema: JSONValue, data: JSONValue) -> Set<String> {
        var required = Set(schema.formStrings("required"))
        for conditional in schema.formObject?["allOf"]?.formArray ?? [] {
            guard let condition = conditional.formObject?["if"] else { continue }
            let branch = matches(data, schema: condition) ? conditional.formObject?["then"] : conditional.formObject?["else"]
            if let branch {
                required.formUnion(branch.formStrings("required"))
                required.formUnion(effectiveRequired(branch, data: data))
            }
        }
        return required
    }

    /// A small JSON Schema evaluator for `if` clauses. Blank strings count as
    /// missing, matching how the web form strips empty answers.
    static func matches(_ value: JSONValue, schema: JSONValue) -> Bool {
        guard let object = schema.formObject else { return schema.formBool ?? true }
        if let constant = object["const"], value != constant { return false }
        if let options = object["enum"]?.formArray, !options.contains(value) { return false }
        if let type = FieldKindResolver.schemaType(schema), !matchesType(value, type) { return false }
        if let required = object["required"]?.formArray?.compactMap(\.formString) {
            let data = value.formObject ?? [:]
            for key in required where data[key]?.isFormBlank ?? true { return false }
        }
        if let minProperties = schema.formInt("minProperties") {
            let present = value.formObject?.values.filter { !$0.isFormBlank }.count ?? 0
            if present < minProperties { return false }
        }
        if let properties = object["properties"]?.formObject, let data = value.formObject {
            for (key, propertySchema) in properties {
                guard let child = data[key], !child.isFormBlank else { continue }
                if !matches(child, schema: propertySchema) { return false }
            }
        }
        if let contains = object["contains"] {
            guard let items = value.formArray, items.contains(where: { matches($0, schema: contains) }) else { return false }
        }
        if let negated = object["not"], matches(value, schema: negated) { return false }
        if let anyOf = object["anyOf"]?.formArray, !anyOf.contains(where: { matches(value, schema: $0) }) { return false }
        if let allOf = object["allOf"]?.formArray, !allOf.allSatisfy({ matches(value, schema: $0) }) { return false }
        if let oneOf = object["oneOf"]?.formArray, oneOf.filter({ matches(value, schema: $0) }).count != 1 { return false }
        if case let .string(text) = value {
            if let minLength = schema.formInt("minLength"), text.count < minLength { return false }
            if let maxLength = schema.formInt("maxLength"), text.count > maxLength { return false }
            if let pattern = schema.formString("pattern"), !matches(text, pattern: pattern) { return false }
        }
        return true
    }

    // MARK: - Messages

    static func message(_ problem: Problem, _ field: FormField?) -> String {
        let title = field?.title ?? ""
        switch problem {
        case .required:
            switch field?.kind {
            case .select?, .radio?, .multiSelect?, .checkbox?:
                return format("forms.error.required_choice", title)
            case .attachment?, .attachmentArray?:
                return format("forms.error.required_attachment", title)
            default:
                return format("forms.error.required", title)
            }
        case .email: return localized("forms.error.email")
        case .date: return localized("forms.error.date")
        case let .type(type):
            return localized(type == "integer" ? "forms.error.integer" : (type == "number" ? "forms.error.number" : "forms.error.type"))
        case .option: return localized("forms.error.option")
        case .pattern:
            return field?.textFormat == .currency ? localized("forms.error.currency") : format("forms.error.pattern", title)
        case let .minLength(count): return format("forms.error.min_length", count)
        case let .maxLength(count): return format("forms.error.max_length", count)
        case let .exactLength(count): return format("forms.error.exact_length", count)
        case let .minimum(value): return format("forms.error.minimum", FieldKindResolver.display(.number(value)))
        case let .maximum(value): return format("forms.error.maximum", FieldKindResolver.display(.number(value)))
        case let .minItems(count): return format("forms.error.min_items", count)
        case let .maxItems(count): return format("forms.error.max_items", count)
        }
    }

    private static func localized(_ key: String) -> String {
        key.localized(bundle: .module)
    }

    private static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: Locale.current, arguments: arguments)
    }

    private static func deduplicated(_ errors: [FieldError]) -> [FieldError] {
        var seen: Set<String> = []
        return errors.filter { seen.insert($0.path).inserted }
    }
}

enum FormDateFormat {
    static func date(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: text)
    }

    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
