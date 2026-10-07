import Foundation
import SGModels

private enum PathComponent: Equatable {
    case key(String)
    case index(Int)
    case wildcard
}

private struct PopulationRule {
    let targetPath: [PathComponent]
    let fields: [String]
    let order: Double
    let sequence: Int
}

private struct ResolvedPath {
    let path: [PathComponent]
    let value: JSONValue?
}

enum FormRulePopulator {
    private static let populationKeys = ["gg_pre_population", "gg_post_population"]

    static func populate(response: JSONValue, ruleSchema: JSONValue?) -> JSONValue {
        guard let ruleSchema,
              case let .object(values) = response,
              !values.isEmpty
        else {
            return response
        }

        var rules: [PopulationRule] = []
        var sequence = 0
        collectRules(in: ruleSchema, at: [], rules: &rules, sequence: &sequence)

        var populated = response
        let orderedRules = rules.sorted {
            $0.order == $1.order ? $0.sequence < $1.sequence : $0.order < $1.order
        }
        for rule in orderedRules {
            let targetPaths = resolve(rule.targetPath, in: populated).map(\.path)
            for targetPath in targetPaths {
                var total = Decimal.zero
                for field in rule.fields {
                    guard let fieldPath = path(for: field, targetPath: targetPath) else { continue }
                    for resolved in resolve(fieldPath, in: populated) {
                        guard let value = resolved.value else { continue }
                        if case let .array(values) = value {
                            for value in values {
                                total += monetaryValue(value)
                            }
                        } else if case .null = value {
                            continue
                        } else {
                            total += monetaryValue(value)
                        }
                    }
                }
                setValue(.string(format(total)), at: targetPath, in: &populated)
            }
        }
        return populated
    }

    private static func collectRules(
        in node: JSONValue,
        at path: [PathComponent],
        rules: inout [PopulationRule],
        sequence: inout Int
    ) {
        guard case let .object(object) = node else { return }
        let targetPath = object["gg_type"] == .string("array") ? path + [.wildcard] : path

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
            let order: Double
            if case let .number(value)? = rule["order"] {
                order = value
            } else {
                order = 1
            }
            rules.append(
                PopulationRule(
                    targetPath: targetPath,
                    fields: fields,
                    order: order,
                    sequence: sequence
                )
            )
            sequence += 1
        }

        for key in object.keys.sorted()
            where !key.hasPrefix("gg_") && key != "gg_type" {
            guard let child = object[key] else { continue }
            collectRules(in: child, at: targetPath + [.key(key)], rules: &rules, sequence: &sequence)
        }
    }

    private static func path(for field: String, targetPath: [PathComponent]) -> [PathComponent]? {
        if field.hasPrefix("@THIS.") {
            guard let relativePath = components(for: String(field.dropFirst("@THIS.".count))) else {
                return nil
            }
            return Array(targetPath.dropLast()) + relativePath
        }

        let absoluteField = field.hasPrefix("$.") ? String(field.dropFirst(2)) : field
        return components(for: absoluteField)
    }

    private static func components(for path: String) -> [PathComponent]? {
        let segments = path.split(separator: ".", omittingEmptySubsequences: false)
        guard !segments.isEmpty else { return nil }
        var components: [PathComponent] = []
        for segmentValue in segments {
            let segment = String(segmentValue)
            guard !segment.isEmpty else { return nil }
            guard let openingBracket = segment.lastIndex(of: "["),
                  segment.last == "]"
            else {
                components.append(.key(segment))
                continue
            }

            let key = String(segment[..<openingBracket])
            let selectorStart = segment.index(after: openingBracket)
            let selectorEnd = segment.index(before: segment.endIndex)
            let selector = String(segment[selectorStart..<selectorEnd])
            guard !key.isEmpty else { return nil }
            components.append(.key(key))
            if selector == "*" {
                components.append(.wildcard)
            } else if let index = Int(selector), index >= 0 {
                components.append(.index(index))
            } else {
                return nil
            }
        }
        return components
    }

    private static func resolve(_ components: [PathComponent], in root: JSONValue) -> [ResolvedPath] {
        var resolved = [ResolvedPath(path: [], value: root)]
        for component in components {
            var next: [ResolvedPath] = []
            for entry in resolved {
                switch component {
                case let .key(key):
                    if let value = entry.value {
                        guard case let .object(object) = value else { continue }
                        next.append(ResolvedPath(path: entry.path + [.key(key)], value: object[key]))
                    } else {
                        next.append(ResolvedPath(path: entry.path + [.key(key)], value: nil))
                    }
                case let .index(index):
                    guard case let .array(values)? = entry.value,
                          values.indices.contains(index)
                    else {
                        continue
                    }
                    next.append(ResolvedPath(path: entry.path + [.index(index)], value: values[index]))
                case .wildcard:
                    guard case let .array(values)? = entry.value else { continue }
                    for (index, value) in values.enumerated() {
                        next.append(ResolvedPath(path: entry.path + [.index(index)], value: value))
                    }
                }
            }
            resolved = next
            if resolved.isEmpty { break }
        }
        return resolved
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

    private static func setValue(_ value: JSONValue, at path: [PathComponent], in response: inout JSONValue) {
        guard let component = path.first else { return }
        switch component {
        case let .key(key):
            guard case var .object(object) = response else { return }
            if path.count == 1 {
                if let existing = object[key],
                   isContainer(existing) {
                    return
                }
                object[key] = value
            } else {
                var nested: JSONValue
                if let existing = object[key] {
                    nested = existing
                } else {
                    guard case .key = path[1] else { return }
                    nested = .object([:])
                }
                setValue(value, at: Array(path.dropFirst()), in: &nested)
                object[key] = nested
            }
            response = .object(object)
        case let .index(index):
            guard case var .array(values) = response,
                  values.indices.contains(index)
            else {
                return
            }
            if path.count == 1 {
                guard !isContainer(values[index]) else { return }
                values[index] = value
            } else {
                var nested = values[index]
                setValue(value, at: Array(path.dropFirst()), in: &nested)
                values[index] = nested
            }
            response = .array(values)
        case .wildcard:
            return
        }
    }

    private static func isContainer(_ value: JSONValue) -> Bool {
        switch value {
        case .array, .object:
            return true
        default:
            return false
        }
    }
}
