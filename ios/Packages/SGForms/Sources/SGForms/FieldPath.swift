import SGModels

/// A location inside an application response, e.g. `$.applicant.street1` or
/// `$.key_contacts[0].name.first_name` (the same notation the API uses for
/// `form_validation_warnings[].field`).
public struct FieldPath: Hashable, Sendable, CustomStringConvertible {
    public enum Component: Hashable, Sendable {
        case key(String)
        case index(Int)
    }

    public var components: [Component]

    public init(_ components: [Component] = []) {
        self.components = components
    }

    public init(keys: [String]) {
        self.components = keys.map(Component.key)
    }

    /// Parses `$.a.b[0].c` (the leading `$` is optional).
    public init(jsonPath: String) {
        var result: [Component] = []
        var rest = Substring(jsonPath)
        if rest.hasPrefix("$") { rest = rest.dropFirst() }
        var current = ""
        var iterator = rest.makeIterator()
        func flush() {
            if !current.isEmpty { result.append(.key(current)) }
            current = ""
        }
        while let character = iterator.next() {
            switch character {
            case ".":
                flush()
            case "[":
                flush()
                var digits = ""
                while let next = iterator.next(), next != "]" { digits.append(next) }
                if let index = Int(digits) { result.append(.index(index)) }
            default:
                current.append(character)
            }
        }
        flush()
        self.components = result
    }

    public var jsonPath: String {
        components.reduce(into: "$") { result, component in
            switch component {
            case let .key(key): result += ".\(key)"
            case let .index(index): result += "[\(index)]"
            }
        }
    }

    public var description: String { jsonPath }

    public var lastKey: String? {
        for component in components.reversed() {
            if case let .key(key) = component { return key }
        }
        return nil
    }

    public func appending(_ other: FieldPath) -> FieldPath {
        FieldPath(components + other.components)
    }

    public func appending(index: Int) -> FieldPath {
        FieldPath(components + [.index(index)])
    }

    /// Converts a UI-schema `definition` to a data path. `items` steps become
    /// `[0]`-style indexes supplied by `indexes`, in order.
    public init(definition: String, indexes: [Int] = []) {
        var remaining = indexes[...]
        var result: [Component] = []
        let parts = SchemaResolver.segments(of: definition)
        var index = 0
        while index < parts.count {
            if parts[index] == "properties", index + 1 < parts.count {
                result.append(.key(parts[index + 1]))
                index += 2
            } else if parts[index] == "items" {
                result.append(.index(remaining.popFirst() ?? 0))
                index += 1
            } else {
                index += 1
            }
        }
        self.components = result
    }
}

public extension JSONValue {
    /// Reads the value at `path`, or `nil` when any step is missing.
    func value(at path: FieldPath) -> JSONValue? {
        var current: JSONValue = self
        for component in path.components {
            switch (component, current) {
            case let (.key(key), .object(object)):
                guard let next = object[key] else { return nil }
                current = next
            case let (.index(index), .array(array)):
                guard array.indices.contains(index) else { return nil }
                current = array[index]
            default:
                return nil
            }
        }
        return current
    }

    /// Writes `newValue` at `path`, creating intermediate objects and arrays as
    /// needed. Every other key already in the response is preserved. Passing
    /// `nil` removes the key (the web form omits unanswered fields too).
    mutating func setValue(_ newValue: JSONValue?, at path: FieldPath) {
        self = Self.setting(newValue, in: self, at: path.components[...])
    }

    private static func setting(
        _ newValue: JSONValue?,
        in container: JSONValue,
        at path: ArraySlice<FieldPath.Component>
    ) -> JSONValue {
        guard let head = path.first else {
            return newValue ?? .null
        }
        let tail = path.dropFirst()
        switch head {
        case let .key(key):
            var object: [String: JSONValue]
            if case let .object(existing) = container { object = existing } else { object = [:] }
            if tail.isEmpty, newValue == nil {
                object.removeValue(forKey: key)
            } else {
                object[key] = setting(newValue, in: object[key] ?? .null, at: tail)
            }
            return .object(object)
        case let .index(index):
            var array: [JSONValue]
            if case let .array(existing) = container { array = existing } else { array = [] }
            while array.count <= index { array.append(.object([:])) }
            if tail.isEmpty, newValue == nil {
                array[index] = .object([:])
            } else {
                array[index] = setting(newValue, in: array[index], at: tail)
            }
            return .array(array)
        }
    }

    /// Removes the array element at `path` (used to delete a FieldList entry).
    mutating func removeElement(at path: FieldPath) {
        guard case let .index(index)? = path.components.last else { return }
        let parent = FieldPath(Array(path.components.dropLast()))
        guard case var .array(array)? = value(at: parent), array.indices.contains(index) else { return }
        array.remove(at: index)
        setValue(.array(array), at: parent)
    }
}
