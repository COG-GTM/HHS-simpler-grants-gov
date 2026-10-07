import Foundation
import SGModels

enum RequiredFieldValidator {
    static func validate(schema: JSONValue, response: JSONValue) -> [ValidationWarning] {
        var warnings: [ValidationWarning] = []
        validate(schema: schema, value: response, path: "$", warnings: &warnings)
        var seen = Set<String>()
        return warnings.filter { seen.insert("\($0.field)\u{0}\($0.message)").inserted }
    }

    static func minimalInstance(schema: JSONValue) -> JSONValue {
        guard case .object = schema else { return .object([:]) }
        var instance = JSONValue.object([:])
        for _ in 0..<8 {
            let warnings = validate(schema: schema, response: instance)
            guard !warnings.isEmpty else { break }
            for warning in warnings where warning.field.hasPrefix("$.") {
                let path = warning.field.dropFirst(2).split(separator: ".").map(String.init)
                guard let propertySchema = schemaAt(path: path, schema: schema) else { continue }
                setValue(sampleValue(schema: propertySchema), at: path, in: &instance)
            }
        }
        return instance
    }

    private static func validate(
        schema: JSONValue,
        value: JSONValue,
        path: String,
        warnings: inout [ValidationWarning]
    ) {
        guard case let .object(schemaObject) = schema else { return }
        let required = strings(schemaObject["required"])
        let objectValues: [String: JSONValue]
        if case let .object(values) = value {
            objectValues = values
        } else {
            objectValues = [:]
        }
        for key in required where isMissing(objectValues[key]) {
            warnings.append(ValidationWarning(
                field: "\(path).\(key)",
                message: "'\(key)' is a required property",
                type: "required"
            ))
        }

        let properties = mergedProperties(schemaObject)
        for (key, propertySchema) in properties {
            guard let propertyValue = objectValues[key] else { continue }
            validate(schema: propertySchema, value: propertyValue, path: "\(path).\(key)", warnings: &warnings)
        }
        if case let .array(values) = value, let itemSchema = schemaObject["items"] {
            for (index, item) in values.enumerated() {
                validate(schema: itemSchema, value: item, path: "\(path).\(index)", warnings: &warnings)
            }
        }
        if case let .array(prefixItems) = schemaObject["prefixItems"],
           case let .array(values) = value {
            for (index, itemSchema) in prefixItems.enumerated() where index < values.count {
                validate(schema: itemSchema, value: values[index], path: "\(path).\(index)", warnings: &warnings)
            }
        }
        if case let .array(allOf) = schemaObject["allOf"] {
            for component in allOf {
                validate(schema: component, value: value, path: path, warnings: &warnings)
            }
        }
        if let condition = schemaObject["if"] {
            let branch = matches(condition: condition, value: value)
                ? schemaObject["then"]
                : schemaObject["else"]
            if let branch {
                validate(schema: branch, value: value, path: path, warnings: &warnings)
            }
        }
    }

    private static func matches(condition: JSONValue, value: JSONValue) -> Bool {
        guard case let .object(conditionObject) = condition else { return false }
        let required = strings(conditionObject["required"])
        let objectValues: [String: JSONValue]
        if case let .object(values) = value {
            objectValues = values
        } else {
            objectValues = [:]
        }
        guard required.allSatisfy({ objectValues[$0] != nil }) else { return false }
        if case let .array(allOf) = conditionObject["allOf"],
           !allOf.allSatisfy({ matches(condition: $0, value: value) }) {
            return false
        }
        if case let .array(anyOf) = conditionObject["anyOf"],
           !anyOf.contains(where: { matches(condition: $0, value: value) }) {
            return false
        }
        if case let .array(oneOf) = conditionObject["oneOf"],
           oneOf.filter({ matches(condition: $0, value: value) }).count != 1 {
            return false
        }
        if let negated = conditionObject["not"], matches(condition: negated, value: value) {
            return false
        }
        if case let .object(properties) = conditionObject["properties"] {
            for (key, rule) in properties {
                guard let candidate = objectValues[key] else { return false }
                if case let .object(ruleObject) = rule {
                    if let constant = ruleObject["const"], candidate != constant { return false }
                    let allowed = values(ruleObject["enum"])
                    if !allowed.isEmpty && !allowed.contains(candidate) { return false }
                    if let contains = ruleObject["contains"] {
                        guard case let .array(items) = candidate,
                              items.contains(where: { matches(condition: contains, value: $0) })
                        else { return false }
                    }
                    if !matches(condition: rule, value: candidate) { return false }
                }
            }
        }
        return true
    }

    private static func mergedProperties(_ schema: [String: JSONValue]) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        if case let .object(properties) = schema["properties"] {
            result.merge(properties) { _, new in new }
        }
        if case let .array(allOf) = schema["allOf"] {
            for component in allOf {
                guard case let .object(componentObject) = component else { continue }
                result.merge(mergedProperties(componentObject)) { _, new in new }
            }
        }
        return result
    }

    private static func mergedRequired(_ schema: [String: JSONValue]) -> [String] {
        var result = strings(schema["required"])
        if case let .array(allOf) = schema["allOf"] {
            for component in allOf {
                guard case let .object(componentObject) = component else { continue }
                for key in mergedRequired(componentObject) where !result.contains(key) {
                    result.append(key)
                }
            }
        }
        return result
    }

    private static func schemaAt(path: [String], schema: JSONValue) -> JSONValue? {
        guard let first = path.first else { return nil }
        if let index = Int(first) {
            guard let itemSchema = arrayItemSchema(index: index, schema: schema) else { return nil }
            return schemaAt(path: Array(path.dropFirst()), schema: itemSchema)
        }
        guard case let .object(object) = schema else { return nil }
        let properties = mergedProperties(object)
        guard let property = properties[first] else { return nil }
        if path.count == 1 { return property }
        return schemaAt(path: Array(path.dropFirst()), schema: property)
    }

    private static func arrayItemSchema(index: Int, schema: JSONValue) -> JSONValue? {
        guard case let .object(object) = schema else { return nil }
        var schemas: [JSONValue] = []
        if case let .array(prefixItems) = object["prefixItems"], prefixItems.indices.contains(index) {
            schemas.append(prefixItems[index])
        }
        if let items = object["items"] {
            schemas.append(items)
        }
        if case let .array(allOf) = object["allOf"] {
            schemas += allOf.compactMap { arrayItemSchema(index: index, schema: $0) }
        }
        guard !schemas.isEmpty else { return nil }
        return .object(["allOf": .array(schemas)])
    }

    private static func sampleValue(schema: JSONValue) -> JSONValue {
        guard case let .object(object) = schema else { return .string("Sample") }
        if let constant = object["const"] { return constant }
        let allowed = values(object["enum"])
        if let first = allowed.first { return first }
        let nested = mergedProperties(object)
        let required = mergedRequired(object)
        var result: [String: JSONValue] = [:]
        for key in required {
            if let property = nested[key] {
                result[key] = sampleValue(schema: property)
            }
        }
        if !required.isEmpty { return .object(result) }
        if let type = object["type"], case let .string(name) = type {
            switch name {
            case "object": return .object([:])
            case "array":
                let minimumCount: Int
                if case let .number(value)? = object["minItems"] {
                    minimumCount = max(0, Int(value))
                } else {
                    minimumCount = 0
                }
                return .array((0..<minimumCount).map { index in
                    sampleValue(schema: arrayItemSchema(index: index, schema: schema) ?? .object([:]))
                })
            case "boolean": return .bool(false)
            case "integer", "number": return .number(0)
            default: return .string("Sample")
            }
        }
        if !nested.isEmpty { return .object([:]) }
        if case let .array(allOf) = object["allOf"], let first = allOf.first {
            return sampleValue(schema: first)
        }
        return .string("Sample")
    }

    private static func setValue(_ value: JSONValue, at path: [String], in instance: inout JSONValue) {
        guard let first = path.first else { return }
        if let index = Int(first), index >= 0, case var .array(values) = instance {
            while values.count <= index { values.append(.object([:])) }
            if path.count == 1 {
                values[index] = value
            } else {
                var nested = values[index]
                setValue(value, at: Array(path.dropFirst()), in: &nested)
                values[index] = nested
            }
            instance = .array(values)
            return
        }
        guard case var .object(values) = instance else { return }
        if path.count == 1 {
            values[first] = value
        } else {
            var nested = values[first] ?? (Int(path[1]) == nil ? .object([:]) : .array([]))
            setValue(value, at: Array(path.dropFirst()), in: &nested)
            values[first] = nested
        }
        instance = .object(values)
    }

    private static func isMissing(_ value: JSONValue?) -> Bool {
        guard let value else { return true }
        switch value {
        case .null: return true
        case let .string(string): return string.isEmpty
        default: return false
        }
    }

    private static func strings(_ value: JSONValue?) -> [String] {
        guard case let .array(values) = value else { return [] }
        return values.compactMap { if case let .string(string) = $0 { string } else { nil } }
    }

    private static func values(_ value: JSONValue?) -> [JSONValue] {
        guard case let .array(values) = value else { return [] }
        return values
    }
}
