import SGDesign
import SGModels
import SwiftUI
import UniformTypeIdentifiers

/// Renders one field (and, for FieldLists, its entries) at a concrete data path.
struct FormFieldView: View {
    let field: FormField
    let path: FieldPath
    @Binding var values: JSONValue
    let context: FormRenderContext
    var focusedPath: FocusState<String?>.Binding
    var accessibilityFocusedPath: AccessibilityFocusState<String?>.Binding

    private var key: String { path.jsonPath }
    private var error: String? { context.errors[key] }

    var body: some View {
        content
            .id(key)
    }

    @ViewBuilder
    private var content: some View {
        switch field.kind {
        case .heading:
            Text(field.title)
                .font(FormTheme.F.section)
                .foregroundStyle(FormTheme.C.ink)
                .padding(.top, FormTheme.S.s)
                .accessibilityAddTraits(.isHeader)
        case .staticText:
            Text(field.content ?? field.title)
                .font(FormTheme.F.sans(14))
                .foregroundStyle(FormTheme.C.muted)
                .fixedSize(horizontal: false, vertical: true)
        case .fieldList:
            FieldListView(
                field: field,
                path: path,
                values: $values,
                context: context,
                focusedPath: focusedPath,
                accessibilityFocusedPath: accessibilityFocusedPath
            )
        case .table, .finishOnWeb:
            FinishOnWebRow(field: field)
        default:
            if field.isReadOnly {
                labelled { ReadOnlyControl(field: field, value: readOnlyText, verified: isVerified) }
            } else {
                labelled { control }
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch field.kind {
        case .text where field.textFormat == .date:
            DateControl(text: stringBinding, label: field.title, hasError: error != nil)
        case .text:
            TextControl(field: field, text: textBinding, hasError: error != nil, focusKey: key, focusedPath: focusedPath, multiline: false)
        case .textArea:
            TextControl(field: field, text: textBinding, hasError: error != nil, focusKey: key, focusedPath: focusedPath, multiline: true)
        case .select:
            SelectControl(field: field, selection: valueBinding, hasError: error != nil)
        case .radio:
            RadioControl(field: field, selection: valueBinding)
        case .checkbox:
            CheckboxControl(field: field, isOn: boolBinding)
        case .multiSelect:
            MultiSelectControl(field: field, selection: arrayBinding, hasError: error != nil)
        case .attachment, .attachmentArray:
            AttachmentControl(field: field, path: path, value: values.value(at: path), context: context, hasError: error != nil) { id in
                removeAttachment(id)
            }
        default:
            FinishOnWebRow(field: field)
        }
    }

    /// Label above the control, error message below (reference 10).
    private func labelled<Control: View>(@ViewBuilder _ control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: FormTheme.S.s) {
            if field.kind != .checkbox {
                Text(field.title)
                    .font(FormTheme.F.label)
                    .foregroundStyle(FormTheme.C.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            if (field.kind == .text && field.textFormat != .date) || field.kind == .textArea {
                control()
                    .accessibilityFocused(accessibilityFocusedPath, equals: key)
            } else {
                control()
                    .accessibilityElement(children: field.kind == .radio || field.kind == .attachment || field.kind == .attachmentArray ? .contain : .combine)
                    .accessibilityLabel(Text(field.title))
                    .accessibilityValue(Text(accessibilityValue))
                    .accessibilityHint(Text(field.isReadOnly ? "forms.read_only.hint".localized(bundle: .module) : ""))
                    .accessibilityIdentifier("forms.field.\(key)")
                    .accessibilityFocused(accessibilityFocusedPath, equals: key)
            }
            if let error {
                Text(error)
                    .font(FormTheme.F.caption)
                    .foregroundStyle(FormTheme.C.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("forms.error.\(key)")
            }
        }
    }

    private var accessibilityValue: String {
        if field.isReadOnly { return readOnlyText ?? "" }
        guard let value = values.value(at: path) else { return "" }
        switch value {
        case let .array(items):
            return items.map { item in field.options.first { $0.value == item }?.title ?? FieldKindResolver.display(item) }
                .joined(separator: ", ")
        default:
            return field.options.first { $0.value == value }?.title ?? FieldKindResolver.display(value)
        }
    }

    // MARK: Read-only

    private var readOnlyText: String? {
        if let value = values.value(at: path), !value.isFormBlank {
            return FieldKindResolver.display(value)
        }
        return context.prefillValue(for: field, at: path)
    }

    private var isVerified: Bool {
        guard let prefilled = context.prefillValue(for: field, at: path), !prefilled.isEmpty else { return false }
        return readOnlyText == prefilled
    }

    // MARK: Bindings

    private var valueBinding: Binding<JSONValue?> {
        Binding(
            get: { values.value(at: path) },
            set: { values.setValue($0, at: path) }
        )
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: { values.value(at: path)?.formString ?? "" },
            set: { values.setValue($0.isEmpty ? nil : .string($0), at: path) }
        )
    }

    /// Strings for text fields; numbers for `integer`/`number` schemas when the
    /// text parses, so the stored JSON type matches the schema.
    private var textBinding: Binding<String> {
        Binding(
            get: {
                guard let value = values.value(at: path) else { return "" }
                return FieldKindResolver.display(value)
            },
            set: { text in
                if text.isEmpty {
                    values.setValue(nil, at: path)
                } else if field.textFormat == .integer || field.textFormat == .number,
                          let number = Double(text.trimmingCharacters(in: .whitespaces)) {
                    values.setValue(.number(number), at: path)
                } else {
                    values.setValue(.string(text), at: path)
                }
            }
        )
    }

    private func removeAttachment(_ id: String) {
        guard case let .array(items)? = values.value(at: path) else {
            values.setValue(nil, at: path)
            return
        }
        let remaining = items.filter { $0.formString != id }
        values.setValue(remaining.isEmpty ? nil : .array(remaining), at: path)
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { values.value(at: path)?.formBool ?? false },
            set: { values.setValue(.bool($0), at: path) }
        )
    }

    private var arrayBinding: Binding<[JSONValue]> {
        Binding(
            get: { values.value(at: path)?.formArray ?? [] },
            set: { values.setValue($0.isEmpty ? nil : .array($0), at: path) }
        )
    }
}

// MARK: - Control chrome

/// 48 pt input with 12 pt radius: control border, navy + tint ring when
/// focused, red when invalid.
struct InputChrome: ViewModifier {
    var hasError: Bool
    var isFocused: Bool = false
    var fill: Color = FormTheme.C.surface
    var minHeight: CGFloat = FormTheme.controlHeight

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: FormTheme.R.input, style: .continuous)
        content
            .padding(.horizontal, FormTheme.S.l)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(fill, in: shape)
            .overlay(shape.stroke(borderColor, lineWidth: hasError || isFocused ? 1.5 : 1))
            .background(
                shape
                    .inset(by: -3)
                    .stroke(isFocused && !hasError ? FormTheme.C.navyTint : .clear, lineWidth: 3)
            )
    }

    private var borderColor: Color {
        if hasError { return FormTheme.C.red }
        if isFocused { return FormTheme.C.navy }
        return FormTheme.C.control
    }
}

extension View {
    func formInputChrome(hasError: Bool, isFocused: Bool = false, fill: Color = FormTheme.C.surface, minHeight: CGFloat = FormTheme.controlHeight) -> some View {
        modifier(InputChrome(hasError: hasError, isFocused: isFocused, fill: fill, minHeight: minHeight))
    }
}

// MARK: - Text

struct TextControl: View {
    let field: FormField
    @Binding var text: String
    let hasError: Bool
    let focusKey: String
    var focusedPath: FocusState<String?>.Binding
    let multiline: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// What the user typed while focused, so a numeric field showing `1.`
    /// isn't redrawn as `1` from the stored number.
    @State private var draft: String?

    /// Whether the bound value is still the one this draft produced; anything
    /// else means the value changed from outside and the draft is stale.
    static func draft(_ draft: String, matches value: String) -> Bool {
        if draft == value { return true }
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard let typed = Double(trimmed), let stored = Double(value) else { return false }
        return typed == stored
    }

    private var editText: Binding<String> {
        Binding(
            get: { draft ?? text },
            set: { draft = $0; text = $0 }
        )
    }

    var body: some View {
        Group {
            if multiline {
                TextField("", text: editText, axis: .vertical)
                    .lineLimit(4...10)
                    .padding(.vertical, FormTheme.S.m)
                    .accessibilityLabel(Text(field.title))
                    .accessibilityIdentifier("forms.field.\(focusKey)")
            } else if dynamicTypeSize.isAccessibilitySize {
                TextField("", text: editText, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.vertical, FormTheme.S.s)
                    .accessibilityLabel(Text(field.title))
                    .accessibilityIdentifier("forms.field.\(focusKey)")
            } else {
                TextField("", text: editText)
                    .accessibilityLabel(Text(field.title))
                    .accessibilityIdentifier("forms.field.\(focusKey)")
            }
        }
        .font(FormTheme.F.bodyText)
        .foregroundStyle(FormTheme.C.ink)
        .tint(FormTheme.C.navy)
        .focused(focusedPath, equals: focusKey)
        .formTextInput(field.textFormat)
        .formInputChrome(hasError: hasError, isFocused: focusedPath.wrappedValue == focusKey, minHeight: multiline ? 112 : FormTheme.controlHeight)
        .onChange(of: focusedPath.wrappedValue) { _, newValue in
            if newValue != focusKey { draft = nil }
        }
        .onChange(of: text) { _, newValue in
            if let draft, !Self.draft(draft, matches: newValue) { self.draft = nil }
        }
    }
}

private extension View {
    @ViewBuilder
    func keepsMenuOpen() -> some View {
        #if os(iOS)
        self.menuActionDismissBehavior(.disabled)
        #else
        self
        #endif
    }

    @ViewBuilder
    func formTextInput(_ format: TextFormat) -> some View {
        #if os(iOS)
        switch format {
        case .email:
            self.keyboardType(.emailAddress).textContentType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        case .phone:
            self.keyboardType(.phonePad).textContentType(.telephoneNumber)
        case .integer:
            self.keyboardType(.numberPad)
        case .number, .currency:
            self.keyboardType(.decimalPad)
        default:
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - Date

struct DateControl: View {
    @Binding var text: String
    let label: String
    let hasError: Bool

    var body: some View {
        if let date = FormDateFormat.date(from: text) {
            HStack {
                DatePicker(
                    label,
                    selection: Binding(get: { date }, set: { text = FormDateFormat.string(from: $0) }),
                    displayedComponents: .date
                )
                .labelsHidden()
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                Spacer()
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FormTheme.C.subtle)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("forms.date.clear".localized(bundle: .module)))
            }
            .formInputChrome(hasError: hasError)
        } else {
            Button {
                text = FormDateFormat.string(from: Date())
            } label: {
                HStack {
                    Text(text.isEmpty ? "forms.date.add".localized(bundle: .module) : text)
                        .font(FormTheme.F.bodyText)
                        .foregroundStyle(text.isEmpty ? FormTheme.C.subtle : FormTheme.C.ink)
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundStyle(FormTheme.C.muted)
                        .accessibilityHidden(true)
                }
                .formInputChrome(hasError: hasError)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Select

struct SelectControl: View {
    let field: FormField
    @Binding var selection: JSONValue?
    let hasError: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Menu {
            Picker(field.title, selection: pickerBinding) {
                ForEach(field.options) { option in
                    Text(option.title).tag(Optional(option.value))
                }
            }
            if selection != nil {
                Divider()
                Button("forms.select.clear".localized(bundle: .module), role: .destructive) { selection = nil }
            }
        } label: {
            HStack(spacing: FormTheme.S.s) {
                Text(selectedTitle ?? "forms.select.placeholder".localized(bundle: .module))
                    .font(FormTheme.F.bodyText)
                    .foregroundStyle(selectedTitle == nil ? FormTheme.C.muted : FormTheme.C.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: FormTheme.S.s)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FormTheme.C.muted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, FormTheme.S.s)
            .formInputChrome(hasError: hasError)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectedTitle: String? {
        guard let selection else { return nil }
        return field.options.first { $0.value == selection }?.title ?? FieldKindResolver.display(selection)
    }

    private var pickerBinding: Binding<JSONValue?> {
        Binding(get: { selection }, set: { selection = $0 })
    }
}

struct MultiSelectControl: View {
    let field: FormField
    @Binding var selection: [JSONValue]
    let hasError: Bool

    var body: some View {
        Menu {
            ForEach(field.options) { option in
                let isSelected = selection.contains(option.value)
                Button {
                    if isSelected {
                        selection.removeAll { $0 == option.value }
                    } else if field.maxItems.map({ selection.count < $0 }) ?? true {
                        selection.append(option.value)
                    }
                } label: {
                    if isSelected {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
                .disabled(!isSelected && field.maxItems.map { selection.count >= $0 } == true)
            }
        } label: {
            HStack(spacing: FormTheme.S.s) {
                Text(summary ?? "forms.select.placeholder".localized(bundle: .module))
                    .font(FormTheme.F.bodyText)
                    .foregroundStyle(summary == nil ? FormTheme.C.muted : FormTheme.C.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: FormTheme.S.s)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FormTheme.C.muted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, FormTheme.S.s)
            .formInputChrome(hasError: hasError)
            .contentShape(Rectangle())
        }
        .keepsMenuOpen()
        .buttonStyle(.plain)
    }

    private var summary: String? {
        guard !selection.isEmpty else { return nil }
        let titles = selection.map { value in field.options.first { $0.value == value }?.title ?? FieldKindResolver.display(value) }
        return titles.joined(separator: ", ")
    }
}

// MARK: - Radio / checkbox

struct RadioControl: View {
    let field: FormField
    @Binding var selection: JSONValue?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(field.options) { option in
                let isSelected = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: FormTheme.S.m) {
                        ZStack {
                            Circle().stroke(isSelected ? FormTheme.C.navy : FormTheme.C.control, lineWidth: 2)
                            if isSelected { Circle().fill(FormTheme.C.navy).padding(5) }
                        }
                        .frame(width: 22, height: 22)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                        Text(option.title)
                            .font(FormTheme.F.bodyText)
                            .foregroundStyle(FormTheme.C.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(option.title))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

struct CheckboxControl: View {
    let field: FormField
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: FormTheme.S.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? FormTheme.C.navy : FormTheme.C.surface)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isOn ? FormTheme.C.navy : FormTheme.C.control, lineWidth: 2)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
                Text(field.title)
                    .font(FormTheme.F.sans(15))
                    .foregroundStyle(FormTheme.C.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Read-only

struct ReadOnlyControl: View {
    let field: FormField
    let value: String?
    let verified: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: FormTheme.S.xs))
            : AnyLayout(HStackLayout(spacing: FormTheme.S.s))
        layout {
            Text(value ?? "forms.read_only.empty".localized(bundle: .module))
                .font(value == nil ? FormTheme.F.sans(15) : FormTheme.F.mono)
                .foregroundStyle(value == nil ? FormTheme.C.subtle : FormTheme.C.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: FormTheme.S.s)
            }
            if verified {
                HStack(spacing: FormTheme.S.xs) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .accessibilityHidden(true)
                    Text("forms.verified".localized(bundle: .module))
                        .font(FormTheme.F.sans(13, .semibold))
                        .fixedSize()
                }
                .foregroundStyle(FormTheme.C.green)
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? FormTheme.S.s : 0)
        .formInputChrome(hasError: false, fill: FormTheme.C.canvas)
    }
}

// MARK: - Finish on web

struct FinishOnWebRow: View {
    let field: FormField

    var body: some View {
        HStack(alignment: .top, spacing: FormTheme.S.m) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 18))
                .foregroundStyle(FormTheme.C.navy)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FormTheme.S.xs) {
                Text("forms.finish_on_web.title".localized(bundle: .module))
                    .font(FormTheme.F.sans(15, .semibold))
                    .foregroundStyle(FormTheme.C.ink)
                Text(detail)
                    .font(FormTheme.F.sans(14))
                    .foregroundStyle(FormTheme.C.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(FormTheme.S.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FormTheme.C.navyTint, in: RoundedRectangle(cornerRadius: FormTheme.R.row, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("forms.finish_on_web.\(field.id)")
    }

    private var detail: String {
        if field.kind == .table, !field.tableColumns.isEmpty {
            return String(format: "forms.finish_on_web.table_detail".localized(bundle: .module), field.title, field.tableColumns.count)
        }
        return String(format: "forms.finish_on_web.detail".localized(bundle: .module), field.title)
    }
}

// MARK: - Attachments

struct AttachmentControl: View {
    let field: FormField
    let path: FieldPath
    let value: JSONValue?
    let context: FormRenderContext
    let hasError: Bool
    let onRemove: (String) -> Void

    @State private var isImporting = false

    private var remainingSlots: Int? {
        guard field.kind == .attachmentArray, let maxItems = field.maxItems else { return nil }
        return max(maxItems - ids.count, 0)
    }

    private var ids: [String] {
        switch value {
        case let .string(id)?: return [id]
        case let .array(items)?: return items.compactMap(\.formString)
        default: return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FormTheme.S.s) {
            ForEach(ids, id: \.self) { id in
                HStack(spacing: FormTheme.S.m) {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(FormTheme.C.navy)
                        .accessibilityHidden(true)
                    Text(context.attachmentNames[id] ?? "forms.attachment.attached".localized(bundle: .module))
                        .font(FormTheme.F.bodyText)
                        .foregroundStyle(FormTheme.C.ink)
                        .lineLimit(1)
                    Spacer()
                    Button("forms.attachment.remove".localized(bundle: .module), role: .destructive) { onRemove(id) }
                        .font(FormTheme.F.sans(14, .semibold))
                        .frame(minHeight: 44)
                        .accessibilityLabel(Text(String(
                            format: "forms.attachment.remove_label".localized(bundle: .module),
                            context.attachmentNames[id] ?? field.title
                        )))
                }
                .formInputChrome(hasError: false)
            }
            Button {
                isImporting = true
            } label: {
                HStack(spacing: FormTheme.S.s) {
                    Image(systemName: "paperclip")
                        .accessibilityHidden(true)
                    Text(buttonTitle)
                        .font(FormTheme.F.sans(15, .semibold))
                    Spacer()
                    if ids.isEmpty {
                        Text("forms.attachment.none".localized(bundle: .module))
                            .font(FormTheme.F.caption)
                            .foregroundStyle(FormTheme.C.subtle)
                    }
                }
                .foregroundStyle(FormTheme.C.navy)
                .formInputChrome(hasError: hasError)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(remainingSlots == 0)
            .accessibilityLabel(Text("\(buttonTitle), \(field.title)"))
            .accessibilityIdentifier("forms.attachment.choose.\(path.jsonPath)")
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item],
            allowsMultipleSelection: field.kind == .attachmentArray
        ) { result in
            guard case let .success(picked) = result else { return }
            let urls = remainingSlots.map { Array(picked.prefix($0)) } ?? picked
            guard !urls.isEmpty else { return }
            context.onAttach?(FormAttachmentRequest(field: field, path: path, urls: urls))
        }
    }

    private var buttonTitle: String {
        if field.kind == .attachmentArray { return "forms.attachment.add".localized(bundle: .module) }
        return (ids.isEmpty ? "forms.attachment.choose" : "forms.attachment.replace").localized(bundle: .module)
    }
}

// MARK: - FieldList

struct FieldListView: View {
    let field: FormField
    let path: FieldPath
    @Binding var values: JSONValue
    let context: FormRenderContext
    var focusedPath: FocusState<String?>.Binding
    var accessibilityFocusedPath: AccessibilityFocusState<String?>.Binding

    private var storedCount: Int { values.value(at: path)?.formArray?.count ?? 0 }
    private var entryCount: Int { max(storedCount, field.minItems ?? 0, 1) }
    private var canAdd: Bool { field.maxItems.map { entryCount < $0 } ?? true }
    /// Stored entries can be removed down to `minItems` (zero by default); the
    /// blank placeholder row shown for an empty list has nothing to remove.
    private func canRemove(_ index: Int) -> Bool { index < storedCount && storedCount > (field.minItems ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: FormTheme.S.l) {
            if let description = field.fieldDescription, !description.isEmpty {
                Text(description)
                    .font(FormTheme.F.sans(14))
                    .foregroundStyle(FormTheme.C.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = context.errors[path.jsonPath] {
                Text(error)
                    .font(FormTheme.F.caption)
                    .foregroundStyle(FormTheme.C.red)
            }
            ForEach(0..<entryCount, id: \.self) { index in
                entry(index)
            }
            HStack(spacing: FormTheme.S.m) {
                Button {
                    var items = values.value(at: path)?.formArray ?? []
                    while items.count < entryCount { items.append(.object([:])) }
                    items.append(.object([:]))
                    values.setValue(.array(items), at: path)
                } label: {
                    Label("forms.list.add".localized(bundle: .module), systemImage: "plus.circle.fill")
                        .font(FormTheme.F.sans(15, .semibold))
                        .frame(minHeight: 44)
                }
                .disabled(!canAdd)
                .foregroundStyle(canAdd ? FormTheme.C.navy : FormTheme.C.subtle)
                .accessibilityIdentifier("forms.list.add.\(path.jsonPath)")
                Spacer()
                if let maxItems = field.maxItems {
                    Text(String(format: "forms.list.count".localized(bundle: .module), entryCount, maxItems))
                        .font(FormTheme.F.caption)
                        .foregroundStyle(FormTheme.C.muted)
                }
            }
        }
    }

    private func entry(_ index: Int) -> some View {
        let entryTitle = String(format: "forms.list.entry".localized(bundle: .module), field.title, index + 1)
        return VStack(alignment: .leading, spacing: FormTheme.S.l) {
            HStack {
                Text(entryTitle)
                    .font(FormTheme.F.sans(16, .semibold))
                    .foregroundStyle(FormTheme.C.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if canRemove(index) {
                    Button(role: .destructive) {
                        values.removeElement(at: path.appending(index: index))
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22))
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(FormTheme.C.red)
                    .accessibilityLabel(Text(String(format: "forms.list.remove_label".localized(bundle: .module), field.title, index + 1)))
                    .accessibilityIdentifier("forms.list.remove.\(path.appending(index: index).jsonPath)")
                }
            }
            ForEach(field.children) { child in
                FormFieldView(
                    field: child,
                    path: path.appending(index: index).appending(child.dataPath),
                    values: $values,
                    context: context,
                    focusedPath: focusedPath,
                    accessibilityFocusedPath: accessibilityFocusedPath
                )
            }
        }
        .padding(FormTheme.S.l)
        .background(FormTheme.C.surface, in: RoundedRectangle(cornerRadius: FormTheme.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FormTheme.R.card, style: .continuous).stroke(FormTheme.C.line, lineWidth: 1))
    }
}
