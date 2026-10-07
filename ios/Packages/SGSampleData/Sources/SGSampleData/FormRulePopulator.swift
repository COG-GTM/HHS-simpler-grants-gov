import Foundation
import SGModels

enum FormRulePopulator {
    private static let populationKeys = ["gg_pre_population", "gg_post_population"]

    static func populate(response: JSONValue, ruleSchema: JSONValue?) -> JSONValue {
        guard let ruleSchema,
              case let .object(values) = response,
              !values.isEmpty
        else {
            return response
        }

        var populated = response
        applyRules(in: ruleSchema, at: [], response: &populated)
        return populated
    }

    private static func applyRules(in node: JSONValue, at targetPath: [String], response: inout JSONValue) {
        guard case let .object(object) = node else { return }
        for key in populationKeys {
            guard case let .object(rule)? = object[key],
                  rule["rule"] == .string("sum_monetary")
            else {
                continue
            }
            let fields: [String]
            if case let .array(values)? = rule["fields"] {
                fields = values.compactMap { if case let .string(value) = $0 { value } else { nil } }
            } else {
                fields = []
            }
            let total = fields.reduce(Decimal.zero) { result, field in
                guard !field.contains("["),
                      let fieldPath = path(for: field, targetPath: targetPath),
                      let value = response.value(at: fieldPath)
                else {
                    return result
                }
                return result + monetaryValue(value)
            }
            setValue(.string(format(total)), at: targetPath, in: &response)
        }

        for (key, child) in object where !key.hasPrefix("gg_") {
            applyRules(in: child, at: targetPath + [key], response: &response)
        }
    }

    private static func path(for field: String, targetPath: [String]) -> [String]? {
        let components: [String]
        if field.hasPrefix("$.") {
            components = field.dropFirst(2).split(separator: ".").map(String.init)
        } else {
            components = Array(targetPath.dropLast()) + field.split(separator: ".").map(String.init)
        }
        return components.isEmpty ? nil : components
    }

    private static func monetaryValue(_ value: JSONValue) -> Decimal {
        switch value {
        case let .number(number):
            return Decimal(number)
        case let .string(string):
            let normalized = string
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) ?? .zero
        default:
            return .zero
        }
    }

    private static func format(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
    }

    private static func setValue(_ value: JSONValue, at path: [String], in response: inout JSONValue) {
        guard let key = path.first,
              case var .object(object) = response
        else {
            return
        }
        if path.count == 1 {
            object[key] = value
        } else {
            var nested = object[key] ?? .object([:])
            setValue(value, at: Array(path.dropFirst()), in: &nested)
            object[key] = nested
        }
        response = .object(object)
    }
}
