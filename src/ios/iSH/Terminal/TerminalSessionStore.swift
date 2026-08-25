//
//  TerminalSessionStore.swift
//  MinisApp
//
//  Persistent terminal sessions (tabs) for the shell. Each TerminalSession
//  owns an ISHTerminalViewModel (emulator + kernel TTY routing) and lives in
//  the store for as long as the app runs, so switching tabs or dismissing the
//  terminal view never kills the shell. On app relaunch the kernel is gone,
//  so the store starts empty and the first tab boots a fresh session.
//

import Foundation
import Combine

/// One persistent terminal (tab).
@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var title: String
    /// False once the kernel reports the session's shell process exited.
    @Published var isRunning = true
    /// The view model driving this session's emulator and TTY routing.
    let viewModel = ISHTerminalViewModel()

    init(title: String) {
        self.title = title
    }
}

/// Holds all terminal sessions; the active one is displayed by the terminal
/// view. Sessions survive tab switches and terminal-view dismissal.
@MainActor
final class TerminalSessionStore: ObservableObject {
    static let shared = TerminalSessionStore()

    @Published var sessions: [TerminalSession] = []
    @Published var activeSessionID: UUID?

    var activeSession: TerminalSession? {
        if let active = sessions.first(where: { $0.id == activeSessionID }) {
            return active
        }
        return sessions.first
    }

    func activate(_ session: TerminalSession) {
        activeSessionID = session.id
    }

    /// Return the active session, creating (and booting) one if needed.
    @discardableResult
    func ensureActiveSession(sessionId: String? = nil, initCommand: String? = nil) -> TerminalSession {
        if let active = activeSession {
            return active
        }
        return newSession(sessionId: sessionId, initCommand: initCommand)
    }

    /// Create a new tab: spawns a fresh login shell on its own kernel
    /// pseudo-terminal. The first session also boots the kernel (installs the
    /// rootfs if needed, applies mounts and environment).
    @discardableResult
    func newSession(sessionId: String? = nil, initCommand: String? = nil) -> TerminalSession {
        let index = sessions.count + 1
        let session = TerminalSession(title: sessionId != nil ? "Agent Shell" : "Shell \(index)")
        sessions.append(session)
        activeSessionID = session.id

        session.viewModel.configureForTerminalMode()
        session.viewModel.startShell(sessionId: sessionId, initCommand: initCommand)
        return session
    }

    /// Kill the session's shell and remove the tab.
    func closeSession(_ session: TerminalSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions.remove(at: index)
        if session.viewModel.terminalHandle > 0 {
            ISHKernel.shared.terminateTerminal(session.viewModel.terminalHandle)
        }
        if activeSessionID == session.id {
            activeSessionID = sessions.last?.id
        }
    }

    /// Mark the session whose kernel terminal exited (shell died).
    func markExited(handle: Int32) {
        guard let session = sessions.first(where: { $0.viewModel.terminalHandle == handle }) else { return }
        session.isRunning = false
        if !session.title.contains("exited") {
            session.title += " (exited)"
        }
    }
}
