//
//  KeyboardShortcutSettingsView.swift
//  MinisApp
//
//  Settings screen for configuring terminal keyboard shortcuts:
//  - list / add / edit / delete custom shortcuts
//  - record a hardware key combination, then choose what it does
//  - options for the built-in Ctrl / Alt / Backspace behavior
//

import SwiftUI
import UIKit

// MARK: - Settings screen

/// Settings screen for terminal keyboard shortcuts.
struct KeyboardShortcutSettingsView: View {
    @ObservedObject private var settings = KeyboardShortcutSettings.shared
    @State private var editor: EditorState?

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

            Section("Key Behavior") {
                Toggle("Ctrl sends control codes", isOn: $settings.ctrlSendsControlCodes)
                Toggle("Alt sends Esc + key (Meta)", isOn: $settings.altSendsEsc)
                Toggle("Backspace sends DEL (0x7F)", isOn: $settings.backspaceSendsDel)
            } footer: {
                Text("When Ctrl or Alt handling is off, those combinations fall through to the system instead of the terminal.")
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
    @State private var flags: UInt = 0
    @State private var isCapturing = false

    // Action state
    @State private var actionKind: ActionKind = .controlCode
    @State private var controlByte: UInt8 = 3
    @State private var textPayload = ""
    @State private var hexPayload = ""

    enum ActionKind: String, CaseIterable, Identifiable {
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
            Section("Action") {
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
        let action: KeyboardShortcutAction
        switch actionKind {
        case .controlCode:
            action = .controlCode(controlByte)
        case .sendText:
            action = .sendText(textPayload)
        case .sendHex:
            action = .sendHex(hexPayload)
        case .paste:
            action = .paste
        case .toggleKeyboard:
            action = .toggleKeyboard
        case .clearScreen:
            action = .clearScreen
        }
        let binding = KeyboardShortcutBinding(
            id: existing?.id ?? UUID(),
            input: input,
            modifierFlags: flags,
            action: action
        )
        onSave(binding)
        dismiss()
    }
}

// MARK: - Key capture

/// UIViewRepresentable wrapper that becomes first responder and reports the
/// next hardware key combination pressed (with at least one of Ctrl / Alt /
/// ⌘, or a special key such as an arrow or F-key).
private struct KeyCaptureBox: UIViewRepresentable {
    var onCapture: (String, UInt) -> Void
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
/// pressesBegan. Suppresses the software keyboard while capturing.
private final class KeyCaptureView: UIView {
    var onCapture: ((String, UInt) -> Void)?
    var onCancel: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Hide the software keyboard — we only care about hardware keys here.
        inputView = UIView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        inputView = UIView()
    }

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
