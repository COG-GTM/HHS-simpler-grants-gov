import SGDesign
import SGModels
import SwiftUI

/// Files picked for an Attachment / AttachmentArray field. Uploading is the
/// caller's job; write the returned attachment id(s) back into `values` at `path`.
public struct FormAttachmentRequest: Sendable {
    public let field: FormField
    public let path: FieldPath
    public let urls: [URL]
}

/// Renders one form section natively. Validation is not run here: the screen
/// calls `FormValidator.validate` on "Save and continue" and passes `errors` in.
/// When `errors` changes to a non-empty list, the first invalid field is
/// scrolled to, focused, and the errors are announced to VoiceOver.
public struct FormSectionView: View {
    private let section: FormSection
    @Binding private var values: JSONValue
    private let errors: [FieldError]
    private let prefill: [String: String]
    private let showsTitle: Bool
    private let attachmentNames: [String: String]
    private let onAttach: ((FormAttachmentRequest) -> Void)?

    @FocusState private var focusedPath: String?
    @AccessibilityFocusState private var accessibilityFocusedPath: String?

    public init(
        section: FormSection,
        values: Binding<JSONValue>,
        errors: [FieldError],
        prefill: [String: String]
    ) {
        self.init(section: section, values: values, errors: errors, prefill: prefill, showsTitle: true)
    }

    /// - Parameters:
    ///   - prefill: Values from the organization / SAM.gov record, keyed by
    ///     JSON path (`$.sam_uei`) or property name (`sam_uei`). Read-only
    ///     fields show these with a "Verified" tag.
    ///   - attachmentNames: Display names for attachment ids already in `values`.
    ///   - onAttach: Called with the files picked in `fileImporter`.
    public init(
        section: FormSection,
        values: Binding<JSONValue>,
        errors: [FieldError],
        prefill: [String: String],
        showsTitle: Bool,
        attachmentNames: [String: String] = [:],
        onAttach: ((FormAttachmentRequest) -> Void)? = nil
    ) {
        self.section = section
        _values = values
        self.errors = errors
        self.prefill = prefill
        self.showsTitle = showsTitle
        self.attachmentNames = attachmentNames
        self.onAttach = onAttach
    }

    public var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: FormTheme.S.l) {
                if showsTitle, !section.title.isEmpty {
                    Text(section.title)
                        .font(FormTheme.F.section)
                        .foregroundStyle(FormTheme.C.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(section.fields) { field in
                    FormFieldView(
                        field: field,
                        path: field.dataPath,
                        values: $values,
                        context: context,
                        focusedPath: $focusedPath,
                        accessibilityFocusedPath: $accessibilityFocusedPath
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: errors) { _, newErrors in
                guard let first = newErrors.first else { return }
                withAnimation { proxy.scrollTo(first.path, anchor: .top) }
                focusedPath = first.path
                accessibilityFocusedPath = first.path
                announce(newErrors)
            }
        }
    }

    private var context: FormRenderContext {
        FormRenderContext(
            errors: Dictionary(errors.map { ($0.path, $0.message) }, uniquingKeysWith: { first, _ in first }),
            prefill: prefill,
            attachmentNames: attachmentNames,
            onAttach: onAttach
        )
    }

    private func announce(_ errors: [FieldError]) {
        let firstMessage = errors.first?.message ?? ""
        let text: String
        if errors.count == 1 {
            text = String(format: "forms.errors.announcement_one".localized(bundle: .module), firstMessage)
        } else {
            text = String(format: "forms.errors.announcement_many".localized(bundle: .module), errors.count, firstMessage)
        }
        AccessibilityNotification.Announcement(text).post()
    }
}

struct FormRenderContext {
    let errors: [String: String]
    let prefill: [String: String]
    let attachmentNames: [String: String]
    let onAttach: ((FormAttachmentRequest) -> Void)?

    func prefillValue(for field: FormField, at path: FieldPath) -> String? {
        prefill[path.jsonPath]
            ?? prefill[field.path]
            ?? path.lastKey.flatMap { prefill[$0] }
    }
}
