import Foundation
import SGModels

/// Turns the custom UI schema (see `frontend/src/components/apply-form/README.md`)
/// into sections and fields.
struct UISchemaParser {
    let resolver: SchemaResolver
    private(set) var unresolved: [String] = []
    private var usedIDs: Set<String> = []

    init(resolver: SchemaResolver) {
        self.resolver = resolver
    }

    mutating func parseTopLevel(_ uiSchema: JSONValue) -> [FormSection] {
        let nodes: [JSONValue]
        switch uiSchema {
        case let .array(array): nodes = array
        case .object: nodes = [uiSchema]
        default: nodes = []
        }

        var sections: [FormSection] = []
        var looseFields: [FormField] = []
        for (index, node) in nodes.enumerated() {
            if node.formString("type") == "section" {
                if !looseFields.isEmpty {
                    sections.append(FormSection(id: uniqueID("section-\(index)"), title: "", fields: looseFields))
                    looseFields = []
                }
                sections.append(parseSection(node, index: index))
            } else {
                looseFields += parseNode(node, listDefinition: nil)
            }
        }
        if !looseFields.isEmpty {
            sections.append(FormSection(id: uniqueID("section-\(nodes.count)"), title: "", fields: looseFields))
        }
        return sections
    }

    /// Used when a form has no UI schema: one section with every root property.
    mutating func fallbackSection(title: String) -> FormSection {
        let root = resolver.resolve(resolver.root)
        let names = root.formObject?["properties"]?.formObject?.keys.sorted() ?? []
        let fields = names.flatMap { name in
            parseNode(.object(["type": .string("field"), "definition": .string("/properties/\(name)")]), listDefinition: nil)
        }
        return FormSection(id: uniqueID("application"), title: title, fields: fields)
    }

    private mutating func parseSection(_ node: JSONValue, index: Int) -> FormSection {
        let name = node.formString("name") ?? "section-\(index + 1)"
        let fields = (node.formObject?["children"]?.formArray ?? []).flatMap {
            parseNode($0, listDefinition: nil)
        }
        return FormSection(
            id: uniqueID(name),
            title: node.formString("label") ?? name,
            fields: fields,
            description: node.formString("description")
        )
    }

    /// Parses one UI node. `listDefinition` is the FieldList's array definition
    /// (e.g. `/properties/key_contacts`) when parsing list children.
    private mutating func parseNode(_ node: JSONValue, listDefinition: String?) -> [FormField] {
        switch node.formString("type") {
        case "section":
            let label = node.formString("label") ?? node.formString("name") ?? ""
            let heading = FormField(
                id: uniqueID("heading-\(node.formString("name") ?? label)"),
                path: "",
                title: label,
                schema: .object([:]),
                kind: .heading,
                dataPath: FieldPath(),
                fieldDescription: node.formString("description")
            )
            let children = (node.formObject?["children"]?.formArray ?? []).flatMap {
                parseNode($0, listDefinition: listDefinition)
            }
            return [heading] + children
        case "text":
            let name = node.formString("name") ?? "text"
            return [FormField(
                id: uniqueID("text-\(name)"),
                path: "",
                title: node.formString("label") ?? "",
                schema: .object([:]),
                kind: .staticText,
                dataPath: FieldPath(),
                content: node.formString("content") ?? node.formString("description")
            )]
        case "fieldList":
            return [parseFieldList(node)]
        case "multiField":
            return [parseMultiField(node)]
        case "field", "null":
            return parseField(node, listDefinition: listDefinition).map { [$0] } ?? []
        default:
            return []
        }
    }

    private mutating func parseField(_ node: JSONValue, listDefinition: String?) -> FormField? {
        let override = node.formObject?["schema"]
        let definition: String
        if let pointer = node.formString("definition") {
            definition = pointer
        } else if let pointer = node.formObject?["definition"]?.formArray?.first?.formString {
            definition = pointer
        } else if let name = node.formString("name") {
            definition = "/properties/\(name)"
        } else {
            return nil
        }

        var schema: JSONValue
        if let resolved = resolver.schema(at: definition) {
            schema = resolved
        } else if override != nil {
            schema = .object([:])
        } else {
            unresolved.append(definition)
            return FormField(
                id: uniqueID(definition),
                path: definition,
                title: node.formString("label") ?? FieldPath(definition: definition).lastKey ?? definition,
                schema: .object([:]),
                kind: .finishOnWeb,
                dataPath: relativePath(definition, listDefinition: listDefinition)
            )
        }
        if let override {
            let resolvedOverride = resolver.resolve(override).formObject ?? [:]
            schema = .object(SchemaResolver.merge(schema.formObject ?? [:], resolvedOverride))
        }

        let widget = node.formString("widget")
        let kind = FieldKindResolver.kind(widget: widget, schema: schema)
        let dataPath = relativePath(definition, listDefinition: listDefinition)
        let isNullNode = node.formString("type") == "null"
        return FormField(
            id: uniqueID(node.formString("name").map { listDefinition == nil ? $0 : "\(listDefinition!)/\($0)" } ?? definition),
            path: definition,
            title: schema.formString("title") ?? Self.humanize(dataPath.lastKey ?? definition),
            schema: schema,
            kind: kind,
            textFormat: FieldKindResolver.textFormat(schema: schema, propertyName: dataPath.lastKey),
            dataPath: dataPath,
            fieldDescription: schema.formString("description"),
            isReadOnly: isNullNode || schema.formObject?["readOnly"] == .bool(true),
            options: FieldKindResolver.options(for: schema, kind: kind),
            widget: widget,
            minItems: schema.formInt("minItems"),
            maxItems: schema.formInt("maxItems")
        )
    }

    private mutating func parseFieldList(_ node: JSONValue) -> FormField {
        let name = node.formString("name") ?? "list"
        let childNodes = node.formObject?["children"]?.formArray ?? []
        let firstDefinition = childNodes.lazy.compactMap { $0.formString("definition") }.first
        let listDefinition: String
        if let firstDefinition, let range = firstDefinition.range(of: "/items") {
            listDefinition = String(firstDefinition[..<range.lowerBound])
        } else {
            listDefinition = "/properties/\(name)"
        }
        let listSchema = resolver.schema(at: listDefinition)
        if listSchema == nil { unresolved.append(listDefinition) }
        let children = childNodes.flatMap { parseNode($0, listDefinition: listDefinition) }
        let schema = listSchema ?? .object([:])
        return FormField(
            id: uniqueID(name),
            path: listDefinition,
            title: node.formString("label") ?? schema.formString("title") ?? Self.humanize(name),
            schema: schema,
            kind: listSchema == nil ? .finishOnWeb : .fieldList,
            dataPath: FieldPath(definition: listDefinition),
            fieldDescription: node.formString("description") ?? schema.formString("description"),
            children: children,
            widget: "FieldList",
            minItems: schema.formInt("minItems"),
            maxItems: schema.formInt("maxItems")
        )
    }

    private mutating func parseMultiField(_ node: JSONValue) -> FormField {
        let definitions: [String]
        if let list = node.formObject?["definition"]?.formArray {
            definitions = list.compactMap(\.formString)
        } else if let single = node.formString("definition") {
            definitions = [single]
        } else {
            definitions = []
        }
        for definition in definitions where resolver.schema(at: definition) == nil {
            unresolved.append(definition)
        }
        let widget = node.formString("widget")
        let name = node.formString("name") ?? definitions.first ?? "multiField"
        let first = definitions.first.flatMap { resolver.schema(at: $0) } ?? .object([:])
        let columns = node.formObject?["children"]?.formObject?["columns"]?.formArray?
            .compactMap { $0.formString("columnHeader") } ?? []
        return FormField(
            id: uniqueID(name),
            path: definitions.first ?? "",
            title: node.formString("label") ?? first.formString("title") ?? Self.humanize(name),
            schema: first,
            kind: widget == "Table" ? .table : .finishOnWeb,
            dataPath: definitions.first.map { FieldPath(definition: $0) } ?? FieldPath(),
            fieldDescription: first.formString("description"),
            widget: widget,
            definitions: definitions,
            tableColumns: columns
        )
    }

    private func relativePath(_ definition: String, listDefinition: String?) -> FieldPath {
        let full = FieldPath(definition: definition)
        guard let listDefinition else { return full }
        let prefix = FieldPath(definition: listDefinition).components.count + 1
        guard full.components.count >= prefix else { return full }
        return FieldPath(Array(full.components.dropFirst(prefix)))
    }

    private mutating func uniqueID(_ base: String) -> String {
        var candidate = base
        var counter = 2
        while usedIDs.contains(candidate) {
            candidate = "\(base)-\(counter)"
            counter += 1
        }
        usedIDs.insert(candidate)
        return candidate
    }

    static func humanize(_ name: String) -> String {
        let words = name.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

/// Groups consecutive sections into the steps shown by the segmented progress bar.
enum FormStepPlanner {
    static let targetStepCount = 5

    /// Curated groupings, keyed by `short_form_name` prefix. Each entry lists the
    /// section names that start a new step. Sections in between join the step.
    static let curatedPlans: [(prefix: String, starts: [(section: String, titleKey: String)])] = [
        ("SF424_4", [
            ("submission_type", "forms.step.sf424.application_type"),
            ("applicant_information", "forms.step.sf424.applicant_information"),
            ("federal_agency", "forms.step.sf424.funding_opportunity"),
            ("areas_affected", "forms.step.sf424.project"),
            ("state_review", "forms.step.sf424.review_and_sign")
        ])
    ]

    static func steps(for sections: [FormSection], shortFormName: String?) -> [FormStep] {
        guard !sections.isEmpty else { return [] }
        if let shortFormName,
           let plan = curatedPlans.first(where: { shortFormName.hasPrefix($0.prefix) }),
           let steps = curated(plan.starts, sections: sections) {
            return steps
        }
        return balanced(sections)
    }

    private static func curated(
        _ starts: [(section: String, titleKey: String)],
        sections: [FormSection]
    ) -> [FormStep]? {
        let ids = sections.map(\.id)
        let indexes = starts.compactMap { ids.firstIndex(of: $0.section) }
        guard indexes.count == starts.count, indexes == indexes.sorted(), indexes.first == 0 else { return nil }
        return indexes.enumerated().map { offset, start in
            let end = offset + 1 < indexes.count ? indexes[offset + 1] : sections.count
            return FormStep(
                id: "step-\(offset + 1)",
                title: NSLocalizedString(starts[offset].titleKey, bundle: .module, comment: ""),
                sections: Array(sections[start..<end])
            )
        }
    }

    /// Splits sections into at most `targetStepCount` consecutive groups with
    /// roughly equal numbers of fields.
    private static func balanced(_ sections: [FormSection]) -> [FormStep] {
        let count = min(targetStepCount, sections.count)
        let weights = sections.map { max(1, $0.fields.count) }
        let total = weights.reduce(0, +)
        var groups: [[FormSection]] = []
        var current: [FormSection] = []
        var accumulated = 0
        for (index, section) in sections.enumerated() {
            current.append(section)
            accumulated += weights[index]
            let remainingSections = sections.count - index - 1
            let remainingGroups = count - groups.count - 1
            let threshold = Double(total) * Double(groups.count + 1) / Double(count)
            if remainingGroups > 0,
               Double(accumulated) >= threshold || remainingSections == remainingGroups {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups.enumerated().map { offset, group in
            FormStep(id: "step-\(offset + 1)", title: stepTitle(group), sections: group)
        }
    }

    /// "8. Applicant Information" -> "Applicant Information".
    static func stepTitle(_ group: [FormSection]) -> String {
        let title = group.first(where: { !$0.title.isEmpty })?.title ?? ""
        return stripNumbering(title)
    }

    static func stripNumbering(_ title: String) -> String {
        let pattern = #"^\s*[0-9]+[a-z]?\.\s+"#
        guard let range = title.range(of: pattern, options: .regularExpression) else { return title }
        return String(title[range.upperBound...])
    }
}
