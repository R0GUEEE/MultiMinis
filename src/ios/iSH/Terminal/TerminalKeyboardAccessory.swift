//
//  TerminalKeyboardAccessory.swift
//  MinisApp
//
//  Quick command bar displayed above the keyboard. The buttons shown
//  (and their order) come from KeyboardShortcutSettings, so users can
//  show/hide/reorder the built-in buttons or add fully custom ones.
//

import SwiftUI

/// Quick command bar displayed above the keyboard
struct TerminalKeyboardAccessory: View {
    /// Send raw bytes to the terminal
    var onInput: (Data) -> Void

    /// Sticky Ctrl modifier
    @Binding var ctrlActive: Bool

    /// Show file browser
    var onShowFileBrowser: () -> Void

    /// Show rootfs management
    var onShowRootfsManagement: () -> Void

    /// Whether the input view is first responder (controls keyboard input)
    @Binding var keyboardActive: Bool

    /// Whether the software keyboard is currently visible
    var softwareKeyboardVisible: Bool = false

    /// Paste the system pasteboard contents into the terminal.
    /// Provided by the host so the same rendering-safe path is reused
    /// (clears selection before feeding bytes to the emulator).
    var onPaste: () -> Void = {}

    /// Invoked when a custom toolbar button bound to "Clear screen" fires.
    var onClearScreen: () -> Void = {}

    @ObservedObject private var settings = KeyboardShortcutSettings.shared

    /// Whether the "123" toggle is on — shows the extra number/symbol row
    /// above the main toolbar (iSH-AOK style).
    @State private var showNumberRow = false

    var body: some View {
        VStack(spacing: 4) {
            if showNumberRow {
                numberRow
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(settings.accessoryButtons.filter(\.enabled)) { button in
                        if let kind = button.kind {
                            builtInButton(kind)
                        } else {
                            customButton(button)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
        }
        .padding(.vertical, 4)
        .background(Color(white: 0.12))
    }

    /// Fixed second row of number / symbol keys shown when the "123" toggle
    /// is on — characters a shell user reaches for constantly.
    private var numberRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array("1234567890-=[]\\;',./"), id: \.self) { char in
                    QuickCommandButton(label: String(char), icon: "") {
                        onInput(String(char).data(using: .utf8) ?? Data())
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        }
    }

    // MARK: - Button rendering

    @ViewBuilder
    private func builtInButton(_ kind: AccessoryButtonKind) -> some View {
        switch kind {
        case .keyboardToggle:
            // Keyboard toggle — shows/hides the software keyboard.
            // The label reflects actual software keyboard visibility.
            // When keyboard is hidden but input view is first responder
            // (external keyboard scenario), tapping Show re-focuses to
            // bring up the software keyboard.
            QuickCommandButton(
                label: softwareKeyboardVisible ? String(localized: "Hide") : String(localized: "Show"),
                icon: softwareKeyboardVisible ? "keyboard.chevron.compact.down" : "keyboard"
            ) {
                toggleKeyboard()
            }

        case .paste:
            // Paste — reuses the same path the long-press edit menu uses
            // (clears any lingering selection before feeding pasteboard
            // bytes into the emulator, so rendering is not gated).
            QuickCommandButton(label: String(localized: "Paste"), icon: "doc.on.clipboard") {
                onPaste()
            }

        case .escape:
            QuickCommandButton(label: "Esc", icon: "escape") {
                onInput(Data([0x1B]))
            }

        case .tab:
            QuickCommandButton(label: "Tab", icon: "arrow.right.to.line") {
                onInput(Data([0x09]))
            }

        case .enter:
            // Enter — the iPad software keyboard's Return inserts a newline
            // (multi-line input) inside the terminal, so it can't send a
            // real carriage return to run a command line / trigger an
            // in-CLI prompt. This writes CR (0x0D) on the same raw-input
            // path as the other keys. [T-ios-shell-toolbar-enter-key]
            QuickCommandButton(label: "\u{23CE}", icon: "return") {
                onInput(Data([0x0D]))
            }

        case .ctrl:
            // Ctrl (sticky modifier)
            QuickCommandButton(label: "Ctrl", icon: "control", isActive: ctrlActive) {
                ctrlActive.toggle()
            }

        case .arrowUp:
            QuickCommandButton(label: "\u{2191}", icon: "chevron.up") {
                sendArrow(.up)
            }
        case .arrowDown:
            QuickCommandButton(label: "\u{2193}", icon: "chevron.down") {
                sendArrow(.down)
            }
        case .arrowLeft:
            QuickCommandButton(label: "\u{2190}", icon: "chevron.left") {
                sendArrow(.left)
            }
        case .arrowRight:
            QuickCommandButton(label: "\u{2192}", icon: "chevron.right") {
                sendArrow(.right)
            }

        case .ctrlC:
            QuickCommandButton(label: "C-c", icon: "xmark.circle") {
                onInput(Data([0x03])) // Ctrl+C
            }
        case .ctrlD:
            QuickCommandButton(label: "C-d", icon: "eject") {
                onInput(Data([0x04])) // Ctrl+D
            }
        case .ctrlZ:
            QuickCommandButton(label: "C-z", icon: "pause.circle") {
                onInput(Data([0x1A])) // Ctrl+Z
            }

        // Center punctuation keys (iSH-AOK style)
        case .dash:
            QuickCommandButton(label: "-", icon: "minus") {
                onInput(Data("-".utf8))
            }
        case .dot:
            QuickCommandButton(label: ".", icon: "circle.fill") {
                onInput(Data(".".utf8))
            }
        case .slash:
            QuickCommandButton(label: "/", icon: "forward.slash") {
                onInput(Data("/".utf8))
            }
        case .colon:
            QuickCommandButton(label: ":", icon: "character.textbox") {
                onInput(Data(":".utf8))
            }
        case .bang:
            QuickCommandButton(label: "!", icon: "exclamationmark") {
                onInput(Data("!".utf8))
            }
        case .pipe:
            QuickCommandButton(label: "|", icon: "line.diagonal") {
                onInput(Data("|".utf8))
            }

        case .numberRow:
            // Toggles the extra number/symbol row above the toolbar.
            QuickCommandButton(label: "123", icon: "number", isActive: showNumberRow) {
                showNumberRow.toggle()
            }

        case .files:
            QuickCommandButton(label: "Files", icon: "folder") {
                onShowFileBrowser()
            }

        case .rootfs:
            QuickCommandButton(label: "Rootfs", icon: "gear") {
                onShowRootfsManagement()
            }
        }
    }

    private func customButton(_ button: AccessoryBarButton) -> some View {
        QuickCommandButton(label: button.title, icon: button.icon) {
            if let action = button.action {
                perform(action)
            }
        }
    }

    // MARK: - Actions

    /// Executes a shortcut action from a custom toolbar button.
    private func perform(_ action: KeyboardShortcutAction) {
        switch action {
        case .controlCode(let code):
            onInput(Data([code]))
        case .sendText(let text):
            if let data = text.data(using: .utf8) {
                onInput(data)
            }
        case .sendHex(let hex):
            if let data = Data(hexString: hex) {
                onInput(data)
            }
        case .paste:
            onPaste()
        case .toggleKeyboard:
            toggleKeyboard()
        case .clearScreen:
            onClearScreen()
        }
    }

    /// Show / hide the software keyboard. If the keyboard is hidden but the
    /// input view is still first responder (external keyboard / user swiped
    /// it away), toggle off-then-on to force a fresh becomeFirstResponder
    /// cycle; otherwise just (de)activate.
    private func toggleKeyboard() {
        if softwareKeyboardVisible {
            // Hide: resign first responder to dismiss keyboard
            keyboardActive = false
        } else if keyboardActive {
            // Keyboard hidden but already first responder:
            keyboardActive = false
            DispatchQueue.main.async { keyboardActive = true }
        } else {
            // Not active: become first responder to show keyboard
            keyboardActive = true
        }
    }

    private func sendArrow(_ direction: ArrowDirection) {
        // Always send normal mode sequences from the accessory bar
        let code: UInt8
        switch direction {
        case .up:    code = 0x41
        case .down:  code = 0x42
        case .right: code = 0x43
        case .left:  code = 0x44
        }
        onInput(Data([0x1B, 0x5B, code]))
    }
}
