import SGDesign
import SGModels
import SwiftUI

public struct FormSectionView: View {
    private let section: FormSection
    @Binding private var values: JSONValue
    private let errors: [FieldError]
    private let prefill: [String: String]

    public init(
        section: FormSection,
        values: Binding<JSONValue>,
        errors: [FieldError],
        prefill: [String: String]
    ) {
        self.section = section
        _values = values
        self.errors = errors
        self.prefill = prefill
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("forms.finish_on_simpler_grants".localized(bundle: .module))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}
