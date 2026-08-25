//
//  KeyboardShortcutSettings.swift
//  MinisApp
//
//  Configurable keyboard shortcuts for the terminal. Users can remap key
//  combinations (Ctrl / Alt / ⌘ / ⇧ + key, or special keys like arrows and
//  F-keys) to send custom byte sequences or trigger app actions such as
//  paste, toggle keyboard, or clear screen.
//
//  The terminal input view (TerminalKeyInputView) reads these settings when
//  building its UIKeyCommand table and when handling physical key presses,
//  so changes apply live without restarting the app.
//

import Foundation
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted whenever the shortcut configuration changes so the terminal
    /// input view can rebuild its UIKeyCommand table.
    static let keyboardShortcutsChanged = Notification.Name("keyboardShortcutsChanged")
}

// MARK: - Action

/// What a keyboard shortcut does when triggered.
enum KeyboardShortcutAction: Codable, Hashable {
    /// Send a raw control character. 1 = Ctrl-A … 26 = Ctrl-Z.
    case controlCode(UInt8)
    /// Send literal text (UTF-8 encoded).
    case sendText(String)
    /// Send raw bytes given as hex, e.g. "1b5b44" for ESC [ D.
    case sendHex(String)
    /// Paste the current clipboard contents into the terminal.
    case paste
    /// Show / hide the software keyboard.
    case toggleKeyboard
    /// Clear the terminal screen.
    case clearScreen

    var displayName: String {
        switch self {
        case .controlCode(let code):
            let letter: String
            if code >= 1 && code <= 26, let scalar = UnicodeScalar(0x40 + Int(code)) {
                letter = String(scalar)
            } else {
                letter = "?"
            }
            return "Send Ctrl-\(letter)"
        case .sendText(let text):
            let shown = text.isEmpty ? "—" : text.replacingOccurrences(of: "\n", with: "⏎")
            return "Send text “\(shown)”"
        case .sendHex(let hex):
            let shown = hex.isEmpty ? "—" : hex.uppercased()
            return "Send bytes 0x\(shown)"
        case .paste:
            return "Paste from clipboard"
        case .toggleKeyboard:
            return "Toggle keyboard"
        case .clearScreen:
            return "Clear screen"
        }
    }
}

// MARK: - Binding

/// A single configurable shortcut: one key combination mapped to one action.
struct KeyboardShortcutBinding: Identifiable, Codable, Hashable {
    var id: UUID
    /// Single character as reported by the hardware key, or a special-key
    /// token such as "UP", "ESC", "F5"…
    var input: String
    /// Raw value of `UIKeyModifierFlags` (command / shift / control / alternate).
    var modifierFlags: UInt
    var action: KeyboardShortcutAction

    var displayName: String {
        KeyboardShortcutFormatter.displayName(input: input, flags: modifierFlags)
    }
}

// MARK: - Formatting helpers

enum KeyboardShortcutFormatter {
    /// "⌃⌥⇧⌘" symbols for the given flags, in the order UIKit displays them.
    static func symbol(for flags: UIKeyModifierFlags) -> String {
        var out = ""
        if flags.contains(.control) { out += "⌃" }
        if flags.contains(.alternate) { out += "⌥" }
        if flags.contains(.shift) { out += "⇧" }
        if flags.contains(.command) { out += "⌘" }
        return out
    }

    /// Human-readable name for a key input string or special-key token.
    static func keyName(for input: String) -> String {
        switch input {
        case "UP": return "↑"
        case "DOWN": return "↓"
        case "LEFT": return "←"
        case "RIGHT": return "→"
        case "ESC": return "Esc"
        case "TAB": return "Tab"
        case "BACKSPACE": return "⌫"
        case "DEL": return "⌦"
        case "HOME": return "Home"
        case "END": return "End"
        case "PGUP": return "PgUp"
        case "PGDN": return "PgDn"
        case "RETURN": return "⏎"
        case " ": return "Space"
        default:
            if input.count == 1 {
                return input.uppercased()
            }
            return input
        }
    }

    static func displayName(input: String, flags: UInt) -> String {
        symbol(for: UIKeyModifierFlags(rawValue: flags)) + keyName(for: input)
    }
}

// MARK: - Special keys

/// Stable tokens for hardware keys that cannot be expressed as a printable
/// UIKeyCommand input (arrows, Esc, F-keys, …). Bindings whose `input` is a
/// token are matched in `pressesBegan` instead of the keyCommands table.
enum KeyboardSpecialKey {
    static let tokens: Set<String> = [
        "UP", "DOWN", "LEFT", "RIGHT", "ESC", "TAB", "BACKSPACE", "DEL",
        "HOME", "END", "PGUP", "PGDN", "RETURN",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    ]

    static func isSpecialToken(_ input: String) -> Bool {
        tokens.contains(input)
    }

    /// Maps a hardware key code to its binding token, if it is a special key.
    static func token(for keyCode: UIKeyboardHIDUsage) -> String? {
        switch keyCode {
        case .keyboardUpArrow: return "UP"
        case .keyboardDownArrow: return "DOWN"
        case .keyboardLeftArrow: return "LEFT"
        case .keyboardRightArrow: return "RIGHT"
        case .keyboardEscape: return "ESC"
        case .keyboardTab: return "TAB"
        case .keyboardDeleteOrBackspace: return "BACKSPACE"
        case .keyboardDeleteForward: return "DEL"
        case .keyboardHome: return "HOME"
        case .keyboardEnd: return "END"
        case .keyboardPageUp: return "PGUP"
        case .keyboardPageDown: return "PGDN"
        case .keyboardReturn, .keyboardReturnSecondary, .keyboardKeypadEnter: return "RETURN"
        case .keyboardSpacebar: return " "
        case .keyboardF1: return "F1"
        case .keyboardF2: return "F2"
        case .keyboardF3: return "F3"
        case .keyboardF4: return "F4"
        case .keyboardF5: return "F5"
        case .keyboardF6: return "F6"
        case .keyboardF7: return "F7"
        case .keyboardF8: return "F8"
        case .keyboardF9: return "F9"
        case .keyboardF10: return "F10"
        case .keyboardF11: return "F11"
        case .keyboardF12: return "F12"
        default: return nil
        }
    }
}

// MARK: - Hex parsing

extension Data {
    /// Parses "1b 5b 44", "1B5B44", "0x1b,0x5b,0x44" style hex into bytes.
    /// Returns nil if the string is empty or malformed.
    init?(hexString: String) {
        let clean = hexString
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !clean.isEmpty,
              clean.count.isMultiple(of: 2),
              clean.allSatisfy({ $0.isHexDigit }) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}

// MARK: - Settings store

/// Centralised, UserDefaults-backed configuration for terminal keyboard
/// shortcuts. Mirrors the FontSettings pattern: a MainActor singleton that
/// publishes changes and posts a notification so UIKit views can react.
@MainActor
final class KeyboardShortcutSettings: ObservableObject {
    static let shared = KeyboardShortcutSettings()

    // MARK: - Published state

    @Published var bindings: [KeyboardShortcutBinding] {
        didSet {
            guard bindings != oldValue else { return }
            saveBindings()
            notifyChanged()
        }
    }
    @Published var ctrlSendsControlCodes: Bool {
        didSet {
            guard ctrlSendsControlCodes != oldValue else { return }
            saveOptions()
            notifyChanged()
        }
    }
    @Published var altSendsEsc: Bool {
        didSet {
            guard altSendsEsc != oldValue else { return }
            saveOptions()
            notifyChanged()
        }
    }
    @Published var backspaceSendsDel: Bool {
        didSet {
            guard backspaceSendsDel != oldValue else { return }
            saveOptions()
            notifyChanged()
        }
    }

    /// Default shortcuts shipped with the app. ⌘V pastes, ⌘C sends Ctrl-C
    /// (SIGINT) like a desktop terminal, ⌘L clears the screen.
    static let defaultBindings: [KeyboardShortcutBinding] = [
        KeyboardShortcutBinding(
            id: UUID(),
            input: "v",
            modifierFlags: UIKeyModifierFlags.command.rawValue,
            action: .paste
        ),
        KeyboardShortcutBinding(
            id: UUID(),
            input: "c",
            modifierFlags: UIKeyModifierFlags.command.rawValue,
            action: .controlCode(3)
        ),
        KeyboardShortcutBinding(
            id: UUID(),
            input: "l",
            modifierFlags: UIKeyModifierFlags.command.rawValue,
            action: .clearScreen
        ),
    ]

    // MARK: - Init

    private init() {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: Keys.bindings),
           let decoded = try? JSONDecoder().decode([KeyboardShortcutBinding].self, from: data) {
            bindings = decoded
        } else {
            bindings = Self.defaultBindings
        }
        ctrlSendsControlCodes = ud.object(forKey: Keys.ctrlSendsControlCodes) as? Bool ?? true
        altSendsEsc = ud.object(forKey: Keys.altSendsEsc) as? Bool ?? true
        backspaceSendsDel = ud.object(forKey: Keys.backspaceSendsDel) as? Bool ?? true
    }

    // MARK: - Lookup

    /// Exact match: same key input AND same modifier bitmask.
    func binding(input: String, flags: UInt) -> KeyboardShortcutBinding? {
        bindings.first { $0.input == input && $0.modifierFlags == flags }
    }

    /// Whether a built-in command for this combo is overridden by a custom binding.
    func isOverridden(input: String, flags: UIKeyModifierFlags) -> Bool {
        binding(input: input, flags: flags.rawValue) != nil
    }

    // MARK: - Reset

    func restoreDefaults() {
        bindings = Self.defaultBindings
        ctrlSendsControlCodes = true
        altSendsEsc = true
        backspaceSendsDel = true
    }

    // MARK: - Persistence

    private func saveBindings() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Keys.bindings)
        }
    }

    private func saveOptions() {
        let ud = UserDefaults.standard
        ud.set(ctrlSendsControlCodes, forKey: Keys.ctrlSendsControlCodes)
        ud.set(altSendsEsc, forKey: Keys.altSendsEsc)
        ud.set(backspaceSendsDel, forKey: Keys.backspaceSendsDel)
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .keyboardShortcutsChanged, object: nil)
    }

    // MARK: - Keys

    private enum Keys {
        static let bindings = "keyboardShortcuts.bindings"
        static let ctrlSendsControlCodes = "keyboardShortcuts.ctrlSendsControlCodes"
        static let altSendsEsc = "keyboardShortcuts.altSendsEsc"
        static let backspaceSendsDel = "keyboardShortcuts.backspaceSendsDel"
    }
}
