import SGModels
import SwiftUI

/// Bundled sample forms and pre-built SF-424 scenarios for SwiftUI previews and
/// snapshot hosts. Dummy data only; nothing here talks to an API.
public enum FormPreviewSamples {
    public enum SF424Scenario: CaseIterable, Sendable {
        /// The five fields shown in reference 10, valid values.
        case referenceFields
        /// Same fields with an invalid email after "Save and continue".
        case invalidEmail
        /// Every section of step 2, empty, after "Save and continue".
        case fullStepEmpty
    }

    /// The full SF-424 definition as exported from the API form registry.
    public static func sf424Definition() throws -> FormDefinition {
        guard let url = Bundle.module.url(forResource: "SF424_4_0", withExtension: "json", subdirectory: "Samples") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder.sg.decode(FormDefinition.self, from: Data(contentsOf: url))
    }

    public static func sf424Model() throws -> FormModel {
        try FormModel(definition: sf424Definition())
    }

    /// Prefill from the (fake) organization / SAM.gov record.
    public static let sf424Prefill = ["sam_uei": "K7LMN2QX4R91"]

    static let referencePointers = [
        "/properties/organization_name", "/properties/sam_uei", "/properties/applicant_type_code",
        "/properties/email", "/properties/phone_number"
    ]

    static var referenceValues: JSONValue {
        .object([
            "organization_name": .string("Bluefield Community Health Center"),
            "applicant_type_code": .array([
                .string("M: Nonprofit with 501C3 IRS Status (Other than Institution of Higher Education)")
            ]),
            "email": .string("dana@bluefieldchc.org"),
            "phone_number": .string("(304) 555-0142"),
            "x_unknown_server_key": .string("kept")
        ])
    }

    /// SF-424 step 2 ("Applicant information") in the given state.
    public static func sf424ApplicantInformation(_ scenario: SF424Scenario) throws -> FormPreviewSample {
        let model = try sf424Model()
        let stepIndex = 1
        let step = model.steps[stepIndex]
        let sections: [FormSection]
        var values: JSONValue
        switch scenario {
        case .referenceFields, .invalidEmail:
            let fields = step.sections.flatMap(\.fields)
            sections = [FormSection(
                id: "reference-10",
                title: "",
                fields: referencePointers.compactMap { pointer in fields.first { $0.path == pointer } }
            )]
            values = referenceValues
            if scenario == .invalidEmail {
                values.setValue(.string("dana@bluefieldchc"), at: FieldPath(keys: ["email"]))
            }
        case .fullStepEmpty:
            sections = step.sections
            values = .object([:])
        }
        let errors = scenario == .referenceFields
            ? []
            : sections.flatMap { FormValidator.validate(values, section: $0, model: model) }
        return FormPreviewSample(
            formTitle: model.formName ?? "",
            stepTitle: step.title,
            stepIndex: stepIndex,
            stepCount: model.steps.count,
            sections: sections,
            values: values,
            errors: errors,
            showsSectionTitles: scenario == .fullStepEmpty
        )
    }
}

public struct FormPreviewSample {
    public let formTitle: String
    public let stepTitle: String
    public let stepIndex: Int
    public let stepCount: Int
    public let sections: [FormSection]
    public let errors: [FieldError]
    let values: JSONValue
    let showsSectionTitles: Bool

    init(formTitle: String, stepTitle: String, stepIndex: Int, stepCount: Int, sections: [FormSection],
         values: JSONValue, errors: [FieldError], showsSectionTitles: Bool) {
        self.formTitle = formTitle
        self.stepTitle = stepTitle
        self.stepIndex = stepIndex
        self.stepCount = stepCount
        self.sections = sections
        self.values = values
        self.errors = errors
        self.showsSectionTitles = showsSectionTitles
    }

    /// The rendered sections, editable in previews.
    @MainActor
    public var content: some View {
        FormPreviewContent(sample: self)
    }
}

private struct FormPreviewContent: View {
    let sample: FormPreviewSample
    @State private var values: JSONValue

    init(sample: FormPreviewSample) {
        self.sample = sample
        _values = State(initialValue: sample.values)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(sample.sections) { section in
                FormSectionView(
                    section: section,
                    values: $values,
                    errors: sample.errors,
                    prefill: FormPreviewSamples.sf424Prefill,
                    showsTitle: sample.showsSectionTitles
                )
            }
        }
    }
}

#Preview("SF-424 applicant information") {
    ScrollView {
        if let sample = try? FormPreviewSamples.sf424ApplicantInformation(.invalidEmail) {
            sample.content.padding(20)
        }
    }
}
