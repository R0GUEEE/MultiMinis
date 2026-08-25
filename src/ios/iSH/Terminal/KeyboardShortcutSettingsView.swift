//
//  KeyboardShortcutSettingsView.swift
//  MinisApp
//
//  Settings screen for configuring terminal keyboard shortcuts:
//  - list / add / edit / delete custom shortcuts
//  - record a hardware key combination, then choose what it does
//  - show / hide / reorder the keyboard toolbar (top bar) buttons and
//    add fully custom toolbar buttons
//  - options for the built-in Ctrl / Alt / Backspace behavior
//

import SwiftUI
import UIKit

// MARK: - Shared action kind

/// What a shortcut / toolbar button sends. Shared by both editors.
fileprivate enum ActionKind: String, CaseIterable, Identifiable {
    case controlCode, sendText, sendHex, paste, toggleKeyboard, clearScreen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .controlCode: return "Control character"
        case .sendText: return "Send text"
        case .sendHex: return "Send hex bytes"
        case .paste: return "Paste from clipboard"
        case .toggleKeyboard: return "Toggle keyboard"
        case .clearScreen: return "Clear screen"
        }
    }
}

/// Builds the KeyboardShortcutAction matching the current ActionKind + payload state.
fileprivate func makeAction(kind: ActionKind, controlByte: UInt8, textPayload: String, hexPayload: String) -> KeyboardShortcutAction {
    switch kind {
    case .controlCode: return .controlCode(controlByte)
    case .sendText: return .sendText(textPayload)
    case .sendHex: return .sendHex(hexPayload)
    case .paste: return .paste
    case .toggleKeyboard: return .toggleKeyboard
    case .clearScreen: return .clearScreen
    }
}

// MARK: - Settings screen

/// Settings screen for terminal keyboard shortcuts.
struct KeyboardShortcutSettingsView: View {
    @ObservedObject private var settings = KeyboardShortcutSettings.shared
    @State private var editor: EditorState?
    @State private var accessoryEditor: AccessoryEditorState?

    /// Which editor sheet is presented (or none).
    enum EditorState: Identifiable {
        case add
        case edit(KeyboardShortcutBinding)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let binding): return binding.id.uuidString
            }
        }

        var existingBinding: KeyboardShortcutBinding? {
            switch self {
            case .add: return nil
            case .edit(let binding): return binding
            }
        }
    }

    /// Which custom-toolbar-button editor sheet is presented (or none).
    enum AccessoryEditorState: Identifiable {
        case add
        case edit(AccessoryBarButton)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let button): return button.id.uuidString
            }
        }

        var existingButton: AccessoryBarButton? {
            switch self {
            case .add: return nil
            case .edit(let button): return button
            }
        }
    }

    var body: some View {
        List {
            Section {
                if settings.bindings.isEmpty {
                    Text("No custom shortcuts. Tap “Add Shortcut” to create one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.bindings) { binding in
                        Button {
                            editor = .edit(binding)
                        } label: {
                            HStack {
                                Text(binding.displayName)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Text(binding.action.displayName)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { indexSet in
                        settings.bindings.remove(atOffsets: indexSet)
                    }
                }

                Button {
                    editor = .add
                } label: {
                    Label("Add Shortcut", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Custom Shortcuts")
            } footer: {
                Text("Shortcuts work with a hardware keyboard and take priority over the built-in Ctrl / Alt handling. “Send bytes” accepts hex like 1b 5b 44 for ESC [ D.")
            }

            Section {
                Toggle("Ctrl sends control codes", isOn: $settings.ctrlSendsControlCodes)
                Toggle("Alt sends Esc + key (Meta)", isOn: $settings.altSendsEsc)
                Toggle("Backspace sends DEL (0x7F)", isOn: $settings.backspaceSendsDel)
            } header: {
                Text("Key Behavior")
            } footer: {
                Text("When Ctrl or Alt handling is off, those combinations fall through to the system instead of the terminal.")
            }

            Section {
                ForEach(settings.accessoryButtons.indices, id: \.self) { index in
                    let button = settings.accessoryButtons[index]
                    HStack {
                        Image(systemName: button.icon)
                            .frame(width: 28)
                            .foregroundStyle(.secondary)
                        Text(button.kind?.displayName ?? button.title)
                        Spacer()
                        if let action = button.action {
                            Text(action.displayName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if button.isCustom {
                            Button {
                                accessoryEditor = .edit(button)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.footnote)
                            }
                            .buttonStyle(.borderless)
                        }
                        Toggle("", isOn: $settings.accessoryButtons[index].enabled)
                            .labelsHidden()
                    }
                }
                .onMove { from, to in
                    settings.accessoryButtons.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { indexSet in
                    // Built-ins are hidden via their toggle instead; only
                    // custom buttons are actually removed here.
                    let customIDs = indexSet.compactMap { idx -> UUID? in
                        settings.accessoryButtons[idx].isCustom ? settings.accessoryButtons[idx].id : nil
                    }
                    settings.accessoryButtons.removeAll { customIDs.contains($0.id) }
                }

                Button {
                    accessoryEditor = .add
                } label: {
                    Label("Add Custom Button", systemImage: "plus.circle.fill")
                }

                Button("Restore Default Toolbar") {
                    settings.restoreDefaultAccessoryButtons()
                }
            } header: {
                Text("Toolbar Buttons")
            } footer: {
                Text("The quick-command bar above the keyboard. Toggle buttons on or off, drag to reorder (Edit), or add custom buttons that send anything.")
            }

            Section {
                Button("Restore Default Shortcuts") {
                    settings.restoreDefaults()
                }
            } footer: {
                Text("Defaults: ⌘V paste, ⌘C send Ctrl-C (SIGINT), ⌘L clear screen.")
            }
        }
        .navigationTitle("Keyboard Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(item: $editor) { state in
            NavigationStack {
                BindingEditorView(existing: state.existingBinding) { newBinding in
                    if let index = settings.bindings.firstIndex(where: { $0.id == newBinding.id }) {
                        settings.bindings[index] = newBinding
                    } else {
                        settings.bindings.append(newBinding)
                    }
                }
            }
        }
        .sheet(item: $accessoryEditor) { state in
            NavigationStack {
                AccessoryButtonEditorView(existing: state.existingButton) { newButton in
                    if let index = settings.accessoryButtons.firstIndex(where: { $0.id == newButton.id }) {
                        settings.accessoryButtons[index] = newButton
                    } else {
                        settings.accessoryButtons.append(newButton)
                    }
                }
            }
        }
    }
}

// MARK: - Binding editor

/// Editor sheet for creating or modifying a single shortcut binding.
private struct BindingEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let existing: KeyboardShortcutBinding?
    var onSave: (KeyboardShortcutBinding) -> Void

    // Key combination state
    @State private var input = ""
    @State private var flags: Int = 0
    @State private var isCapturing = false

    // Action state
    @State private var actionKind: ActionKind = .controlCode
    @State private var controlByte: UInt8 = 3
    @State private var textPayload = ""
    @State private var hexPayload = ""

    private var hexValid: Bool {
        hexPayload.isEmpty || Data(hexString: hexPayload) != nil
    }

    private var canSave: Bool {
        guard !input.isEmpty else { return false }
        switch actionKind {
        case .controlCode: return true
        case .sendText: return !textPayload.isEmpty
        case .sendHex: return hexValid && !hexPayload.isEmpty
        default: return true
        }
    }

    var body: some View {
        Form {
            // MARK: Key combination
            Section {
                if isCapturing {
                    VStack(spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Press a key combination…")
                            .font(.headline)
                        Text("Hold Ctrl / Alt / ⌘ / ⇧ and press a key. Esc alone cancels.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        KeyCaptureBox(
                            onCapture: { capturedInput, capturedFlags in
                                input = capturedInput
                                flags = capturedFlags
                                isCapturing = false
                            },
                            onCancel: {
                                isCapturing = false
                            }
                        )
                        .frame(width: 1, height: 1)
                        Button("Cancel") {
                            isCapturing = false
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Key Combination")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if input.isEmpty {
                                Text("None recorded")
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text(KeyboardShortcutFormatter.displayName(input: input, flags: flags))
                                    .font(.system(.title3, design: .monospaced))
                            }
                        }
                        Spacer()
                        Button("Record") {
                            isCapturing = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } header: {
                Text("Key Combination")
            } footer: {
                Text("Requires a hardware keyboard (e.g. Magic Keyboard or Smart Keyboard Folio).")
            }

            // MARK: Action
            Section {
                ActionEditorFields(
                    actionKind: $actionKind,
                    controlByte: $controlByte,
                    textPayload: $textPayload,
                    hexPayload: $hexPayload
                )
            } header: {
                Text("Action")
            } footer: {
                if actionKind == .sendHex {
                    Text("Bytes are sent raw to the terminal. Example: 1b 5b 44 = ESC [ D (left arrow).")
                }
            }

            Section {
                Button("Save") {
                    save()
                }
                .disabled(!canSave)

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }
        }
        .navigationTitle(existing == nil ? "New Shortcut" : "Edit Shortcut")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadExisting)
    }

    // MARK: Helpers

    private func controlLetter(for byte: Int) -> String {
        guard byte >= 1 && byte <= 26, let scalar = UnicodeScalar(0x40 + byte) else { return "?" }
        return String(scalar)
    }

    private func loadExisting() {
        guard let existing else { return }
        input = existing.input
        flags = existing.modifierFlags
        switch existing.action {
        case .controlCode(let byte):
            actionKind = .controlCode
            controlByte = byte
        case .sendText(let text):
            actionKind = .sendText
            textPayload = text
        case .sendHex(let hex):
            actionKind = .sendHex
            hexPayload = hex
        case .paste:
            actionKind = .paste
        case .toggleKeyboard:
            actionKind = .toggleKeyboard
        case .clearScreen:
            actionKind = .clearScreen
        }
    }

    private func save() {
        let binding = KeyboardShortcutBinding(
            id: existing?.id ?? UUID(),
            input: input,
            modifierFlags: flags,
            action: makeAction(kind: actionKind, controlByte: controlByte, textPayload: textPayload, hexPayload: hexPayload)
        )
        onSave(binding)
        dismiss()
    }
}

// MARK: - Reusable action fields

/// Action picker + payload inputs, shared by the shortcut editor and the
/// custom toolbar button editor.
private struct ActionEditorFields: View {
    @Binding var actionKind: ActionKind
    @Binding var controlByte: UInt8
    @Binding var textPayload: String
    @Binding var hexPayload: String

    private var hexValid: Bool {
        hexPayload.isEmpty || Data(hexString: hexPayload) != nil
    }

    var body: some View {
        Picker("Action", selection: $actionKind) {
            ForEach(ActionKind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }

        switch actionKind {
        case .controlCode:
            Picker("Character", selection: $controlByte) {
                ForEach(1...26, id: \.self) { byte in
                    let letter = controlLetter(for: byte)
                    Text("Ctrl-\(letter)  (0x\(String(byte, radix: 16).uppercased()))")
                        .tag(UInt8(byte))
                }
            }
        case .sendText:
            TextField("e.g. exit⏎", text: $textPayload)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .sendHex:
            TextField("e.g. 1b5b44", text: $hexPayload)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !hexValid {
                Text("Invalid hex — use byte pairs like 1b 5b 44")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        case .paste, .toggleKeyboard, .clearScreen:
            Text(actionKind.label)
                .foregroundStyle(.secondary)
        }
    }

    private func controlLetter(for byte: Int) -> String {
        guard byte >= 1 && byte <= 26, let scalar = UnicodeScalar(0x40 + byte) else { return "?" }
        return String(scalar)
    }
}

// MARK: - Custom toolbar button editor

/// Editor sheet for creating or modifying a custom keyboard toolbar button.
private struct AccessoryButtonEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let existing: AccessoryBarButton?
    var onSave: (AccessoryBarButton) -> Void

    @State private var title = ""
    @State private var icon = "keyboard"
    @State private var actionKind: ActionKind = .controlCode
    @State private var controlByte: UInt8 = 3
    @State private var textPayload = ""
    @State private var hexPayload = ""

    private static let suggestedIcons = [
        "keyboard", "doc.on.clipboard", "escape", "return", "control",
        "chevron.up", "chevron.down", "chevron.left", "chevron.right",
        "xmark.circle", "eject", "pause.circle", "folder", "gear",
        "terminal", "paintbrush", "arrow.clockwise", "paperplane",
    ]

    private var canSave: Bool {
        !title.isEmpty && !icon.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Button label", text: $title)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("SF Symbol name", text: $icon)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Image(systemName: icon)
                        .frame(width: 28)
                        .foregroundStyle(.secondary)
                    Text("Preview")
                        .foregroundStyle(.secondary)
                    Spacer()
                    QuickCommandButton(label: title.isEmpty ? "Btn" : title, icon: icon) {}
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.suggestedIcons, id: \.self) { name in
                            Button {
                                icon = name
                            } label: {
                                Image(systemName: name)
                                    .frame(width: 32, height: 32)
                                    .background(icon == name ? Color.accentColor.opacity(0.25) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(icon == name ? Color.accentColor : .primary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Button")
            } footer: {
                Text("The label and icon appear in the quick-command bar above the keyboard.")
            }

            Section {
                ActionEditorFields(
                    actionKind: $actionKind,
                    controlByte: $controlByte,
                    textPayload: $textPayload,
                    hexPayload: $hexPayload
                )
            } header: {
                Text("Action")
            } footer: {
                if actionKind == .sendHex {
                    Text("Bytes are sent raw to the terminal. Example: 1b 5b 44 = ESC [ D (left arrow).")
                }
            }

            Section {
                Button("Save") {
                    save()
                }
                .disabled(!canSave)

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }
        }
        .navigationTitle(existing == nil ? "New Toolbar Button" : "Edit Toolbar Button")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let existing else { return }
        title = existing.title
        icon = existing.icon
        guard let action = existing.action else {
            actionKind = .controlCode
            return
        }
        switch action {
        case .controlCode(let byte):
            actionKind = .controlCode
            controlByte = byte
        case .sendText(let text):
            actionKind = .sendText
            textPayload = text
        case .sendHex(let hex):
            actionKind = .sendHex
            hexPayload = hex
        case .paste:
            actionKind = .paste
        case .toggleKeyboard:
            actionKind = .toggleKeyboard
        case .clearScreen:
            actionKind = .clearScreen
        }
    }

    private func save() {
        let button = AccessoryBarButton(
            id: existing?.id ?? UUID(),
            title: title,
            icon: icon,
            action: makeAction(kind: actionKind, controlByte: controlByte, textPayload: textPayload, hexPayload: hexPayload),
            enabled: existing?.enabled ?? true
        )
        onSave(button)
        dismiss()
    }
}

// MARK: - Key capture

/// UIViewRepresentable wrapper that becomes first responder and reports the
/// next hardware key combination pressed (with at least one of Ctrl / Alt /
/// ⌘, or a special key such as an arrow or F-key).
private struct KeyCaptureBox: UIViewRepresentable {
    var onCapture: (String, Int) -> Void
    var onCancel: () -> Void

    func makeUIView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: KeyCaptureView, context: Context) {
        uiView.onCapture = onCapture
        uiView.onCancel = onCancel
    }
}

/// Plain UIView that captures hardware key combinations via UIKeyCommand and
/// pressesBegan. A plain (non-text-input) UIView never summons the software
/// keyboard, so capture works silently with a hardware keyboard.
private final class KeyCaptureView: UIView {
    var onCapture: ((String, Int) -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    private static let modifierSets: [UIKeyModifierFlags] = [
        .control,
        .alternate,
        .command,
        [.control, .shift],
        [.alternate, .shift],
        [.command, .shift],
        [.control, .alternate],
        [.command, .alternate],
        [.control, .command],
    ]

    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = []
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let digits = "0123456789"
        for flags in Self.modifierSets {
            for char in letters {
                // Both cases so shift-inclusive combos (e.g. Ctrl+Shift+C)
                // match whichever character iOS reports.
                commands.append(makeCommand(String(char), flags))
                commands.append(makeCommand(String(char).uppercased(), flags))
            }
            for char in digits {
                commands.append(makeCommand(String(char), flags))
            }
        }
        // Punctuation with the most common modifier combos
        for char in "-=[]\\;',./`" {
            commands.append(makeCommand(String(char), .alternate))
            commands.append(makeCommand(String(char), .command))
        }
        return commands
    }

    private func makeCommand(_ input: String, _ flags: UIKeyModifierFlags) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: flags, action: #selector(captureKey(_:)))
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    @objc private func captureKey(_ command: UIKeyCommand) {
        guard let input = command.input, !input.isEmpty else { return }
        onCapture?(input, command.modifierFlags.rawValue)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }

            // Bare Esc cancels the capture instead of being recorded.
            if key.keyCode == .keyboardEscape, key.modifierFlags.isEmpty {
                onCancel?()
                return
            }

            if let token = KeyboardSpecialKey.token(for: key.keyCode) {
                onCapture?(token, key.modifierFlags.rawValue)
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }
}
