//
//  TerminalKeyboardAccessory.swift
//  MinisApp
//
//  Quick command bar displayed above the keyboard, modeled after the
//  iSH-AOK accessory bar:
//    - control keys (Esc / Ctrl / Tab / arrows) on the left
//    - punctuation keys (- . / : ! |) in the center
//    - utility keys (Paste / C-c / 123 / Files / Rootfs / Hide) on the right
//  The bar always fits the screen width — no sideways scrolling. When space
//  is tight (iPhone portrait) the flanking keys are hidden, keeping the
//  essentials visible (same adaptive behavior as iSH-AOK).
//
//  The buttons shown (and their order) come from KeyboardShortcutSettings.
//

import SwiftUI
import UIKit

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

    // Group membership: which kinds belong to which side of the bar.
    private let leftKinds: [AccessoryButtonKind] = [.escape, .ctrl, .tab, .arrows]
    private let centerKinds: [AccessoryButtonKind] = [.dash, .dot, .slash, .colon, .bang, .pipe]
    private let rightKinds: [AccessoryButtonKind] = [.paste, .enter, .ctrlC, .ctrlD, .ctrlZ, .numberRow, .files, .rootfs, .keyboardToggle]

    /// Kinds that survive the compact (narrow) layout.
    private let compactKinds: Set<AccessoryButtonKind> = [
        .escape, .ctrl, .tab, .arrows,
        .dot, .slash,
        .numberRow, .files, .rootfs, .keyboardToggle,
    ]

    var body: some View {
        VStack(spacing: 4) {
            if showNumberRow {
                numberRow
            }
            GeometryReader { geo in
                let compact = geo.size.width < 540
                HStack(spacing: 5) {
                    ForEach(buttons(in: leftKinds, compact: compact)) { button in
                        barButton(button)
                    }
                    Spacer(minLength: 2)
                    ForEach(buttons(in: centerKinds, compact: compact)) { button in
                        barButton(button)
                    }
                    Spacer(minLength: 2)
                    ForEach(buttons(in: rightKinds, compact: compact)) { button in
                        barButton(button)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }
            .frame(height: 34)
        }
        .padding(.vertical, 3)
        .background(Color(white: 0.12))
    }

    /// Enabled buttons from the settings list that belong to `kinds`, in the
    /// user's order. Custom buttons only appear in the wide layout.
    private func buttons(in kinds: [AccessoryButtonKind], compact: Bool) -> [AccessoryBarButton] {
        settings.accessoryButtons.filter { button in
            guard button.enabled else { return false }
            guard let kind = button.kind else { return !compact }
            guard kinds.contains(kind) else { return false }
            if compact { return compactKinds.contains(kind) }
            return true
        }
    }

    @ViewBuilder
    private func barButton(_ button: AccessoryBarButton) -> some View {
        if let kind = button.kind {
            builtInButton(kind)
        } else {
            customButton(button)
        }
    }

    /// Fixed second row of number / symbol keys shown when the "123" toggle
    /// is on — characters a shell user reaches for constantly. Fits the
    /// screen width, no scrolling.
    private var numberRow: some View {
        HStack(spacing: 3) {
            ForEach(Array("1234567890-=[]\\;',./"), id: \.self) { char in
                QuickCommandButton(label: String(char), icon: "") {
                    onInput(String(char).data(using: .utf8) ?? Data())
                }
                .frame(minWidth: 20)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
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
                icon: ""
            ) {
                toggleKeyboard()
            }

        case .paste:
            // Paste — reuses the same path the long-press edit menu uses
            // (clears any lingering selection before feeding pasteboard
            // bytes into the emulator, so rendering is not gated).
            QuickCommandButton(label: String(localized: "Paste"), icon: "") {
                onPaste()
            }

        case .escape:
            QuickCommandButton(label: "Esc", icon: "") {
                onInput(Data([0x1B]))
            }

        case .tab:
            QuickCommandButton(label: "Tab", icon: "") {
                onInput(Data([0x09]))
            }

        case .enter:
            // Enter — the iPad software keyboard's Return inserts a newline
            // (multi-line input) inside the terminal, so it can't send a
            // real carriage return to run a command line / trigger an
            // in-CLI prompt. This writes CR (0x0D) on the same raw-input
            // path as the other keys. [T-ios-shell-toolbar-enter-key]
            QuickCommandButton(label: "\u{23CE}", icon: "") {
                onInput(Data([0x0D]))
            }

        case .ctrl:
            // Ctrl (sticky modifier)
            QuickCommandButton(label: "Ctrl", icon: "", isActive: ctrlActive) {
                ctrlActive.toggle()
            }

        case .arrows:
            // One combined directional key: press and drag toward the
            // direction, hold to auto-repeat, plain tap sends Up.
            ArrowKeyButton { direction in
                sendArrow(direction)
            }

        // Legacy per-direction arrow kinds (migrated to .arrows; kept for
        // decoding persisted layouts).
        case .arrowUp:
            QuickCommandButton(label: "\u{2191}", icon: "") { sendArrow(.up) }
        case .arrowDown:
            QuickCommandButton(label: "\u{2193}", icon: "") { sendArrow(.down) }
        case .arrowLeft:
            QuickCommandButton(label: "\u{2190}", icon: "") { sendArrow(.left) }
        case .arrowRight:
            QuickCommandButton(label: "\u{2192}", icon: "") { sendArrow(.right) }

        case .ctrlC:
            QuickCommandButton(label: "C-c", icon: "") {
                onInput(Data([0x03])) // Ctrl+C
            }
        case .ctrlD:
            QuickCommandButton(label: "C-d", icon: "") {
                onInput(Data([0x04])) // Ctrl+D
            }
        case .ctrlZ:
            QuickCommandButton(label: "C-z", icon: "") {
                onInput(Data([0x1A])) // Ctrl+Z
            }

        // Center punctuation keys (iSH-AOK style)
        case .dash:
            QuickCommandButton(label: "-", icon: "") { onInput(Data("-".utf8)) }
        case .dot:
            QuickCommandButton(label: ".", icon: "") { onInput(Data(".".utf8)) }
        case .slash:
            QuickCommandButton(label: "/", icon: "") { onInput(Data("/".utf8)) }
        case .colon:
            QuickCommandButton(label: ":", icon: "") { onInput(Data(":".utf8)) }
        case .bang:
            QuickCommandButton(label: "!", icon: "") { onInput(Data("!".utf8)) }
        case .pipe:
            QuickCommandButton(label: "|", icon: "") { onInput(Data("|".utf8)) }

        case .numberRow:
            // Toggles the extra number/symbol row above the toolbar.
            QuickCommandButton(label: "123", icon: "", isActive: showNumberRow) {
                showNumberRow.toggle()
            }

        case .files:
            QuickCommandButton(label: "Files", icon: "") {
                onShowFileBrowser()
            }

        case .rootfs:
            QuickCommandButton(label: "Rootfs", icon: "") {
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

// MARK: - Combined arrow key (iSH-AOK style)

/// One key showing all four arrows. Press and drag toward a direction to
/// send it (auto-repeats while held); a plain tap sends Up.
private struct ArrowKeyButton: View {
    var onArrow: (ArrowDirection) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeDirection: ArrowDirection?
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        let tint: Color = colorScheme == .light ? .black : .white
        HStack(spacing: 3) {
            VStack(spacing: 1) {
                Text("\u{25B2}").font(.system(size: 8, weight: .bold))
                Text("\u{25BC}").font(.system(size: 8, weight: .bold))
            }
            VStack(spacing: 1) {
                Text("\u{25C0}").font(.system(size: 8, weight: .bold))
                Text("\u{25B6}").font(.system(size: 8, weight: .bold))
            }
        }
        .foregroundStyle(tint.opacity(activeDirection == nil ? 1 : 0.4))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.15), lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.4), radius: 0, x: 0, y: 1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let direction = direction(for: value.translation)
                    if direction != activeDirection {
                        activeDirection = direction
                        if let direction {
                            fire(direction)
                        }
                    }
                }
                .onEnded { _ in
                    if activeDirection == nil {
                        fire(.up)
                    }
                    stopRepeat()
                    activeDirection = nil
                }
        )
        .onDisappear {
            stopRepeat()
        }
    }

    private var backgroundColor: Color {
        colorScheme == .light ? .white : Color(white: 1.0, opacity: 0.30)
    }

    private func direction(for translation: CGSize) -> ArrowDirection? {
        let dx = translation.width
        let dy = translation.height
        guard abs(dx) > 14 || abs(dy) > 14 else { return nil }
        if abs(dx) > abs(dy) {
            return dx > 0 ? .right : .left
        }
        return dy > 0 ? .down : .up
    }

    /// Send the direction once, then auto-repeat while the finger stays down
    /// (0.5 s delay, then every 0.1 s) — same feel as iSH-AOK's arrow key.
    private func fire(_ direction: ArrowDirection) {
        onArrow(direction)
        repeatTask?.cancel()
        repeatTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            while !Task.isCancelled {
                onArrow(direction)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stopRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}
