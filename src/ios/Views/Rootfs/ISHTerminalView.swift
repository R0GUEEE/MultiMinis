//
//  ISHTerminalView.swift
//  MinisApp
//
//  Terminal view for iSH shell interaction
//

import SwiftUI
import UIKit

struct ISHTerminalView: View {
    var sessionId: String? = nil
    var showCloseButton: Bool = false
    var initCommand: String? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TerminalSessionStore.shared
    @State private var boundSessionCreated = false
    @State private var showFileBrowser = false
    @State private var showRootfsManagement = false
    @State private var showRootfsImport = false
    @State private var showKeyboardShortcuts = false

    /// Track whether a sheet is presented so we can resign first responder
    /// and stop fighting with text fields inside the sheet.
    private var isSheetPresented: Bool {
        showFileBrowser || showRootfsManagement || showRootfsImport || showKeyboardShortcuts
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalTabBar(store: store)
            if let session = store.activeSession {
                TerminalSessionContent(
                    session: session,
                    isTerminalVisible: !isSheetPresented,
                    onShowFileBrowser: { showFileBrowser = true },
                    onShowRootfsManagement: { showRootfsManagement = true }
                )
            } else {
                emptyTabState
            }
        }
        // Terminal fills the full screen — keyboard floats on top.
        // This prevents bounds changes from triggering terminal resize (SIGWINCH).
        .background(Color.black)
        .ignoresSafeArea(.keyboard)
        .navigationTitle("MultiMinis Shell")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showCloseButton {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    store.activeSession?.viewModel.clearScreen()
                } label: {
                    Image(systemName: "paintbrush")
                }
            }
            // Keyboard shortcut configuration
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showKeyboardShortcuts = true
                } label: {
                    Image(systemName: "keyboard.badge.ellipsis")
                }
                .accessibilityLabel("Keyboard Shortcuts")
            }
            // Rootfs / import control: view & switch installed rootfs profiles
            // or import a new tar.gz mini-rootfs.
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showRootfsImport = true
                } label: {
                    Image(systemName: "shippingbox")
                }
                .accessibilityLabel("Rootfs")
            }
        }
        .sheet(isPresented: $showKeyboardShortcuts) {
            NavigationStack {
                KeyboardShortcutSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showKeyboardShortcuts = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showFileBrowser) {
            NavigationStack {
                FileBrowserView()
            }
        }
        .sheet(isPresented: $showRootfsManagement) {
            NavigationStack {
                RootfsManagementView()
            }
        }
        .sheet(isPresented: $showRootfsImport) {
            NavigationStack {
                RootfsImportView()
            }
        }
        .onAppear {
            // Agent-bound opens (sessionId != nil) always create a fresh
            // shell for that chat session; plain opens reuse the persistent
            // tab set from the store.
            if !boundSessionCreated {
                boundSessionCreated = true
                if sessionId != nil {
                    _ = store.newSession(sessionId: sessionId, initCommand: initCommand)
                } else {
                    _ = store.ensureActiveSession()
                }
            }
            // Claim the broker so AIChatView (which sits beneath our
            // fullScreenCover) stops presenting web URLs on top — otherwise
            // its .sheet(item: $safariURL) tries to present while the
            // fullScreenCover is up, SwiftUI dismisses the terminal to make
            // room for the sheet, and the user sees "terminal closes,
            // browser opens, loading forever". Cleared in .onDisappear.
            MinisOpenURLBroker.shared.terminalVisible = true
        }
        .onDisappear {
            MinisOpenURLBroker.shared.terminalVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.ISHTerminalExited)) { note in
            if let handle = note.userInfo?["handle"] as? NSNumber {
                store.markExited(handle: handle.int32Value)
            }
        }
    }

    /// Shown when the last tab was closed and no session remains.
    private var emptyTabState: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(.gray)
            Text("No open terminals")
                .foregroundStyle(.gray)
            Button {
                _ = store.newSession()
            } label: {
                Label("New Shell", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - Terminal tab bar

/// Horizontal strip of persistent terminal tabs + a "new tab" button.
private struct TerminalTabBar: View {
    @ObservedObject var store: TerminalSessionStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.sessions) { session in
                    tabButton(session)
                }
                Button {
                    _ = store.newSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Color(white: 0.25), in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("New Terminal")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(white: 0.09))
    }

    private func tabButton(_ session: TerminalSession) -> some View {
        let isActive = store.activeSession?.id == session.id
        return HStack(spacing: 6) {
            Text(session.title)
                .font(.caption)
                .lineLimit(1)
            if session.isRunning {
                Button {
                    store.closeSession(session)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? Color.black.opacity(0.7) : .gray)
                .accessibilityLabel("Close \(session.title)")
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isActive ? Color(white: 0.95) : Color(white: 0.22),
                    in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(isActive ? Color.black : .white)
        .onTapGesture {
            store.activate(session)
        }
    }
}

// MARK: - Terminal session content

/// The actual terminal UI for one session: canvas, keyboard capture, accessory
/// bar and the keyboard / URL handlers. Only the store's active session is
/// rendered, so these states are per-session by construction.
private struct TerminalSessionContent: View {
    @ObservedObject var session: TerminalSession
    var isTerminalVisible: Bool
    var onShowFileBrowser: () -> Void
    var onShowRootfsManagement: () -> Void

    @State private var ctrlActive = false
    @State private var keyboardActive = true
    /// Whether the software keyboard is currently visible (separate from first
    /// responder state). On Mac Catalyst or iPad with external keyboard, the
    /// software keyboard can be hidden while the input view remains first
    /// responder and continues to receive hardware key events.
    @State private var softwareKeyboardVisible = false
    /// URL captured from an OSC `MinisOpenURL` marker emitted by
    /// /usr/local/bin/minis-open — presented in an in-app WKWebView sheet.
    @State private var linkPreviewURL: URL?

    private var viewModel: ISHTerminalViewModel { session.viewModel }

    var body: some View {
        ZStack {
            TerminalCanvasView(
                emulator: viewModel.emulator,
                onResize: { cols, rows in
                    viewModel.handleResize(cols: cols, rows: rows)
                },
                onPaste: { data in
                    viewModel.sendInput(data)
                },
                onTap: {
                    toggleKeyboard()
                },
                onDoubleTap: {
                    viewModel.sendInput(Data([0x09]))
                }
            )

            // Invisible keyboard input capture
            TerminalInputView(
                onInput: { data in viewModel.sendInput(data) },
                applicationCursorKeys: viewModel.emulator.applicationCursorKeys,
                isActive: $keyboardActive,
                ctrlActive: $ctrlActive,
                isTerminalVisible: isTerminalVisible,
                onToggleKeyboard: {
                    keyboardActive.toggle()
                },
                onClearScreen: {
                    viewModel.clearScreen()
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0)

            if !session.isRunning {
                exitedOverlay
            }
        }
        // Accessory bar is pinned above the keyboard via safeAreaInset and
        // only appears while the software keyboard is visible — like iSH-AOK's
        // inputAccessoryView, it travels with the keyboard instead of being
        // stuck to the bottom of the screen. Tap the terminal to bring both
        // back.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if softwareKeyboardVisible {
                TerminalKeyboardAccessory(
                    onInput: { data in viewModel.sendInput(data) },
                    ctrlActive: $ctrlActive,
                    onShowFileBrowser: onShowFileBrowser,
                    onShowRootfsManagement: onShowRootfsManagement,
                    keyboardActive: $keyboardActive,
                    softwareKeyboardVisible: softwareKeyboardVisible,
                    onPaste: {
                        guard let text = UIPasteboard.general.string, !text.isEmpty,
                              let data = text.data(using: .utf8) else { return }
                        viewModel.sendInput(data)
                    },
                    onClearScreen: {
                        viewModel.clearScreen()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: softwareKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
            TerminalRedrawLog.log("keyboardWillShow endFrame=\(end) active=\(keyboardActive)")
            softwareKeyboardVisible = true
            if isTerminalVisible {
                keyboardActive = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            TerminalRedrawLog.log("keyboardWillHide active=\(keyboardActive)")
            softwareKeyboardVisible = false
            // Do NOT set keyboardActive = false here. On Mac Catalyst and
            // iPad with external keyboard, the software keyboard is hidden
            // but the TerminalKeyInputView must remain first responder to
            // receive hardware key events. Resigning first responder here
            // would break all keyboard input for interactive programs like
            // `gh auth login`, `read`, vim, etc.
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if isTerminalVisible {
                keyboardActive = true
            }
        }
        // In-app WKWebView preview for URLs emitted by `minis-open` via
        // the OSC 1337 MinisOpenURL marker. `TerminalEmulator` parses the
        // marker and forwards the URL through `MinisOpenURLBroker`.
        // `.dropFirst()` skips the broker's current value on first attach
        // so a stale URL from an earlier session isn't re-presented.
        .onReceive(MinisOpenURLBroker.shared.$pendingURL.dropFirst().compactMap { $0 }) { url in
            // Only web schemes are routed here — minis:// resource
            // previews need AIChatView's `handleMinisURLTap` and aren't
            // reachable from the standalone terminal. Consume either way
            // so the broker doesn't leak a stale pendingURL back to chat
            // on next attach.
            if MinisOpenURLBroker.isWebScheme(url.scheme),
               linkPreviewURL?.absoluteString != url.absoluteString {
                linkPreviewURL = url
            }
            MinisOpenURLBroker.shared.consume()
        }
        .sheet(item: $linkPreviewURL) { url in
            // Reuse the exact same preview the AIChat markdown-link tap
            // uses — `MinisLinkPreviewView` with its toolbar (reload /
            // stop / Safari / share / expand to fullscreen). The underlying
            // `WebViewHolder` reads the user's Browser Settings UA and
            // shares the global process pool, so cookies / HSTS state /
            // user agent match the rest of the app. `browserPool: nil`
            // is fine — the preview view doesn't actually use it.
            MinisLinkPreviewView(url: url, browserPool: nil)
        }
    }

    /// Shown when the kernel reports this session's shell exited.
    private var exitedOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("This shell has exited.")
                .foregroundStyle(.white)
            Button {
                _ = TerminalSessionStore.shared.newSession()
            } label: {
                Label("New Shell", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
    }

    private func toggleKeyboard() {
        // Toggle the keyboard. Mirrors TerminalKeyboardAccessory's
        // Show/Hide button: if visible, hide; if hidden but input
        // view is still first responder (external keyboard / user
        // swiped it away), toggle off-then-on to force a fresh
        // becomeFirstResponder cycle; otherwise just activate.
        if softwareKeyboardVisible {
            keyboardActive = false
        } else if keyboardActive {
            keyboardActive = false
            DispatchQueue.main.async { keyboardActive = true }
        } else {
            keyboardActive = true
        }
    }
}

// MARK: - View Model

class ISHTerminalViewModel: ObservableObject {
    let emulator = TerminalEmulator()
    private let logger = AppLogger(category: "ISHTerminalViewModel")

    private var isShellStarted = false

    /// Kernel terminal handle when running in tab mode (a PTY created by
    /// ISHKernel.startNewTerminal…). -1 = legacy single-console mode.
    private(set) var terminalHandle: Int32 = -1
    /// Whether this VM should spawn its shell on its own terminal instead of
    /// the legacy console path (which routes through the global outputCallback).
    private var terminalMode = false

    /// Switch this VM to multi-terminal (tab) mode. Must be called before
    /// startShell.
    func configureForTerminalMode() {
        terminalMode = true
    }

    /// Monotonic token used to detect whether the currently installed global
    /// outputCallback still belongs to this VM instance. See `installedCallbackGeneration`.
    private static var generationCounter: Int = 0
    private static let generationLock = NSLock()
    private static var currentOwnerGeneration: Int = 0
    /// The generation this VM installed when it last called setupOutputCallback.
    /// Used by deinit to avoid clobbering a newer VM's callback during async teardown.
    private var myGeneration: Int = 0

    init() {
        // NOTE: Do NOT install outputCallback here. On iOS 16, SwiftUI may init
        // a provisional @StateObject that it later discards (e.g. during a
        // fullScreenCover body re-evaluation). If we captured self in the C
        // callback here, the captured [weak self] goes nil once SwiftUI drops
        // the provisional VM, and all TTY output is silently discarded — the
        // terminal stays black forever. Install from startShell() (onAppear)
        // instead, by which point @StateObject has committed to storage.
    }

    deinit {
        // Only clear the global callback if WE are the current owner. A newer
        // VM may have taken ownership already — in that case clearing it would
        // strand the new VM with no callback and cause the "second open hangs"
        // bug. Swift ARC runs deinit asynchronously, so it is common for an
        // old VM's deinit to land AFTER a new VM has already installed its
        // own callback in startShell().
        guard !terminalMode else { return } // per-terminal callbacks are owned by the kernel map
        Self.generationLock.lock()
        let owner = Self.currentOwnerGeneration
        Self.generationLock.unlock()
        if owner == myGeneration && myGeneration != 0 {
            ISHKernel.shared.outputCallback = nil
        }
    }

    /// Coalesced output closure that feeds `emulator`. The kernel fires the
    /// TTY callback thousands of times per millisecond with tiny (4–24 byte)
    /// chunks during commands like `ls`; dispatching each chunk to the main
    /// queue floods it and starves touch/keyboard events. Instead: append to
    /// a pending buffer under a lock, and schedule a single main.async only
    /// on the empty→non-empty transition. The main block drains whatever has
    /// accumulated by the time it runs — typically the entire burst.
    private func makeCoalescedOutputClosure() -> ISHOutputCallback {
        let emulator = self.emulator
        let pendingLock = NSLock()
        var pendingData = Data()
        let closure: ISHOutputCallback = { (data: Data) in
            pendingLock.lock()
            let wasEmpty = pendingData.isEmpty
            pendingData.append(data)
            pendingLock.unlock()
            guard wasEmpty else { return }
            DispatchQueue.main.async {
                pendingLock.lock()
                let drained = pendingData
                pendingData.removeAll(keepingCapacity: true)
                pendingLock.unlock()
                guard !drained.isEmpty else { return }
                emulator.feed(drained)
            }
        }
        return closure
    }

    private func setupOutputCallback() {
        Self.generationLock.lock()
        Self.generationCounter += 1
        let gen = Self.generationCounter
        Self.currentOwnerGeneration = gen
        Self.generationLock.unlock()
        myGeneration = gen

        ISHKernel.shared.outputCallback = makeCoalescedOutputClosure()

        // Wire up the terminal → TTY response path so the emulator can reply
        // to queries like DSR (ESC[6n → ESC[row;colR). Without this, programs
        // that query cursor position (e.g. Go's survey library used by gh) will
        // block forever waiting for the response.
        wireResponsePath(emulator: emulator)
    }

    private func wireResponsePath(emulator: TerminalEmulator) {
        emulator.onResponse = { [weak self] data in
            self?.sendInput(data)
        }
    }

    func startShell(sessionId: String? = nil, initCommand: String? = nil) {
        // Console mode installs the global output callback up front (existing
        // behavior). Tab mode registers a per-terminal callback at spawn time
        // instead — never touch the global slot.
        if !terminalMode {
            setupOutputCallback()
        }

        guard !isShellStarted else { return }
        isShellStarted = true

        let totalStart = CFAbsoluteTimeGetCurrent()
        var stepStart = totalStart

        // [T-rootfs-reset-terminal-crash] If the rootfs was reset while the
        // kernel was already booted this session, the kernel's fakefs is mounted
        // against a deleted data/ + meta.db tree. It cannot be re-mounted or
        // un-booted in-process (become_first_process() is irreversible), so
        // reusing it here — the isBooted branch below skips install+boot — drives
        // executeCommand against freed/deleted state and crashes. Refuse to start
        // and tell the user to relaunch, which triggers a fresh install+boot.
        if ISHKernel.shared.isBooted && RootfsManager.shared.didResetWhileBooted {
            isShellStarted = false
            logger.warning("[StartShell] rootfs was reset this session; refusing to reuse stale kernel mount")
            let msg = "\r\n" + String(localized: "The Linux environment was reset. Please restart the app to reinstall it before using the terminal.") + "\r\n"
            if let data = msg.data(using: .utf8) {
                emulator.feed(data)
            }
            return
        }

        // Boot kernel if needed
        if !ISHKernel.shared.isBooted {
            do {
                stepStart = CFAbsoluteTimeGetCurrent()
                try RootfsManager.shared.installIfNeeded()
                logger.info("[StartShell] installIfNeeded: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000))ms")
            } catch {
                let msg = "Failed to install rootfs: \(error.localizedDescription)\r\n"
                if let data = msg.data(using: .utf8) {
                    emulator.feed(data)
                }
                return
            }

            stepStart = CFAbsoluteTimeGetCurrent()
            let rootPath = RootfsManager.shared.rootfsPath.path
            let err = ISHKernel.shared.boot(withRootPath: rootPath)
            logger.info("[StartShell] boot: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000))ms")
            if err < 0 {
                let msg = "Failed to boot kernel: \(err)\r\n"
                if let data = msg.data(using: .utf8) {
                    emulator.feed(data)
                }
                return
            }
        } else {
            logger.info("[StartShell] kernel already booted, skipping install+boot")
        }

        stepStart = CFAbsoluteTimeGetCurrent()
        RootfsManager.shared.applyDefaultMountOverlay()
        logger.info("[StartShell] applyDefaultMountOverlay: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000))ms")

        Task { @MainActor in MirrorSpeedTestViewModel.shared.autoDetectOnceIfNeeded() }

        // Mount /var/minis/* for this session BEFORE starting the shell.
        // We must do this synchronously before executeCommand so the shell sees the mounts.
        // Use Task.detached to avoid inheriting main actor isolation (which would deadlock
        // the semaphore since .onAppear runs on the main actor).
        if let sid = sessionId {
            stepStart = CFAbsoluteTimeGetCurrent()
            print("[ISHTerminal] Mounting /var/minis for session \(sid) before shell start")
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                await ISHExecutionCoordinator.shared.mountForSession(sid)
                semaphore.signal()
            }
            semaphore.wait()
            logger.info("[StartShell] mountForSession: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000))ms")
        }

        // Inject user-defined environment variables
        stepStart = CFAbsoluteTimeGetCurrent()
        let customEnv = EnvVarStore.shared.allAsDict()
        if !customEnv.isEmpty {
            ISHKernel.shared.customEnvironment = customEnv
        }
        logger.info("[StartShell] envVars: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000))ms (\(customEnv.count) vars)")

        // Start shell
        stepStart = CFAbsoluteTimeGetCurrent()
        if terminalMode {
            // Tab mode: spawn a fresh login shell on its own pseudo-terminal.
            // The kernel registers the coalesced callback before dispatching
            // the spawn, so early prompt output is never lost.
            wireResponsePath(emulator: emulator)
            let handle = ISHKernel.shared.startNewTerminal(outputCallback: makeCoalescedOutputClosure())
            if handle < 0 {
                let msg = "Failed to start terminal: \(handle)\r\n"
                if let data = msg.data(using: .utf8) {
                    emulator.feed(data)
                }
                return
            }
            terminalHandle = handle
            logger.info("[StartShell] terminal handle \(handle) started in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000))ms")
        } else {
            // Start as login shell (-l) so /etc/profile and /etc/profile.d/*.sh
            // are sourced, enabling command history and line editing.
            let err = ISHKernel.shared.executeCommand(["/bin/sh", "-l"])
            logger.info("[StartShell] executeCommand(/bin/sh -l): \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000))ms")
            if err < 0 {
                let msg = "Failed to start shell: \(err)\r\n"
                if let data = msg.data(using: .utf8) {
                    emulator.feed(data)
                }
                return
            }
        }

        logger.info("[StartShell] TOTAL: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - totalStart) * 1000))ms (sessionId=\(sessionId ?? "nil"))")

        // If opened from a session, cd to the session's shared directory
        if sessionId != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if let data = "cd /var/minis && clear\n".data(using: .utf8) {
                    self?.sendInput(data)
                }
                // Pre-fill init command (without newline) so the user can review before pressing Enter
                if let cmd = initCommand, !cmd.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if let data = cmd.data(using: .utf8) {
                            self?.sendInput(data)
                        }
                    }
                }
            }
        } else if let cmd = initCommand, !cmd.isEmpty {
            // Pre-fill init command (without newline) after shell starts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if let data = cmd.data(using: .utf8) {
                    self?.sendInput(data)
                }
            }
        }
    }

    /// Serial queue for sending input to the kernel TTY.
    /// tty_input() acquires a pthread mutex that can block when the kernel is busy,
    /// so we must never call it on the main thread.
    private let inputQueue = DispatchQueue(label: "com.openminis.terminal.input")

    func sendInput(_ data: Data) {
        let tEnq = TerminalRedrawLog.nowMs()
        let size = data.count
        let handle = terminalHandle
        inputQueue.async {
            let tDeq = TerminalRedrawLog.nowMs()
            if handle > 0 {
                ISHKernel.shared.sendInput(data, toTerminal: handle)
            } else {
                ISHKernel.shared.sendInput(data)
            }
            let tWrite = TerminalRedrawLog.nowMs()
            TerminalRedrawLog.log(String(format: "sendInput bytes=%d enq->deq=%.1fms write=%.1fms",
                size, tDeq - tEnq, tWrite - tDeq))
        }
    }

    func clearScreen() {
        // Send "clear" command to the shell so it redraws the prompt
        if let data = "clear\n".data(using: .utf8) {
            sendInput(data)
        }
        // Clear scrollback buffer for a completely fresh view
        emulator.activeBuffer.clearScrollback()
    }

    func handleResize(cols: Int, rows: Int) {
        emulator.resize(cols: cols, rows: rows)
        let handle = terminalHandle
        if handle > 0 {
            ISHKernel.shared.setTerminalSize(Int32(cols), rows: Int32(rows), forTerminal: handle)
        } else {
            ISHKernel.shared.setTerminalSize(Int32(cols), rows: Int32(rows))
        }
    }
}

// MARK: - Quick Command Button

/// Key-styled toolbar button matching the iSH-AOK accessory bar look:
/// rounded key with a subtle bottom shadow, colored by the system appearance
/// (white key / black glyph in light mode, translucent key / white glyph in
/// dark mode). `isActive` (e.g. sticky Ctrl) tints it blue.
struct QuickCommandButton: View {
    let label: String
    let icon: String
    var isActive: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(foregroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 0, x: 0, y: 1)
        }
    }

    private var backgroundColor: Color {
        if isActive { return .blue }
        return colorScheme == .light ? .white : Color(white: 1.0, opacity: 0.30)
    }

    private var foregroundColor: Color {
        if isActive { return .white }
        return colorScheme == .light ? .black : .white
    }
}

#Preview {
    NavigationStack {
        ISHTerminalView()
    }
}
