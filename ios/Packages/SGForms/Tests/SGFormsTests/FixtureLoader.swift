import Foundation
import SGModels
@testable import SGForms

enum Fixtures {
    static var formsDirectory: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures/forms", isDirectory: true)
    }

    static func allFormNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: formsDirectory.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }

    static func definition(_ name: String) throws -> FormDefinition {
        let data = try Data(contentsOf: formsDirectory.appendingPathComponent("\(name).json"))
        return try JSONDecoder.sg.decode(FormDefinition.self, from: data)
    }

    static func model(_ name: String) throws -> FormModel {
        try FormModel(definition: definition(name))
    }
}

extension FormModel {
    func field(_ definition: String) -> FormField? {
        for field in allFields {
            if field.path == definition { return field }
            if let child = field.children.first(where: { $0.path == definition }) { return child }
        }
        return nil
    }

    func sectionContaining(_ definition: String) -> FormSection? {
        sections.first { section in
            section.fields.contains { $0.path == definition || $0.children.contains { $0.path == definition } }
        }
    }
}

extension JSONValue: @retroactive ExpressibleByStringLiteral, @retroactive ExpressibleByIntegerLiteral,
    @retroactive ExpressibleByFloatLiteral, @retroactive ExpressibleByBooleanLiteral,
    @retroactive ExpressibleByArrayLiteral, @retroactive ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}
