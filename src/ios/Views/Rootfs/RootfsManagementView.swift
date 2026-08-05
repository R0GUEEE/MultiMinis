//
//  RootfsManagementView.swift
//  MinisApp
//
//  UI for managing rootfs (reset, backup, restore)
//

import SwiftUI

struct RootfsManagementView: View {
    @StateObject private var viewModel = RootfsManagementViewModel()
    @StateObject private var importModel = RootfsImportViewModel()
    @State private var showFileBrowser = false

    var body: some View {
        List {
            Section("Status") {
                HStack {
                    Text("Installed")
                    Spacer()
                    Image(systemName: viewModel.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(viewModel.isInstalled ? .green : .red)
                }

                if viewModel.isInstalled {
                    HStack {
                        Text("Size")
                        Spacer()
                        if viewModel.rootfsSize > 0 {
                            Text(viewModel.formattedSize)
                                .foregroundColor(.secondary)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    HStack {
                        Text("Path")
                        Spacer()
                        Text(viewModel.rootfsPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            if viewModel.isInstalled {
                Section("Browse") {
                    Button(action: { showFileBrowser = true }) {
                        Label {
                            Text("Browse Files")
                        } icon: {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white)
                                .frame(width: 21, height: 21)
                                .background(.blue, in: Circle())
                        }
                    }
                }

                MirrorsSectionView()
            }

            // ---- Import any rootfs.tar.gz and load it (multi-distro) ----
            RootfsImportSection(model: importModel)

            Section("Actions") {
                if !viewModel.isInstalled {
                    Button(action: { viewModel.install() }) {
                        Label {
                            Text("Install Rootfs")
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white)
                                .frame(width: 21, height: 21)
                                .background(.green, in: Circle())
                        }
                    }
                    .disabled(viewModel.isProcessing)
                } else {
                    Button(action: { viewModel.showResetConfirmation = true }) {
                        Label {
                            Text("Reset Rootfs")
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                                .foregroundStyle(.white)
                                .frame(width: 21, height: 21)
                                .background(.orange, in: Circle())
                        }
                    }
                    .disabled(viewModel.isProcessing)

                    Button(action: { viewModel.showResetWithBackupConfirmation = true }) {
                        Label {
                            Text("Reset & Backup User Data")
                        } icon: {
                            Image(systemName: "archivebox.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white)
                                .frame(width: 21, height: 21)
                                .background(.indigo, in: Circle())
                        }
                    }
                    .disabled(viewModel.isProcessing)
                }

                if viewModel.hasBackup {
                    Button(action: { viewModel.restoreBackup() }) {
                        Label {
                            Text("Restore User Data")
                        } icon: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white)
                                .frame(width: 21, height: 21)
                                .background(.teal, in: Circle())
                        }
                    }
                    .disabled(viewModel.isProcessing || !viewModel.isInstalled)
                }
            }

            if viewModel.isProcessing {
                Section {
                    HStack {
                        ProgressView()
                        Text(viewModel.statusMessage)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let message = viewModel.resultMessage {
                Section {
                    Text(message)
                        .font(.callout)
                        .foregroundColor(viewModel.lastOperationSuccess ? .green : .red)
                }
            }

            Section("Info") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About Rootfs")
                        .font(.headline)

                    Text("The rootfs contains the Alpine Linux filesystem. Resetting will delete all data and restore to factory state.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("• Reset: Delete everything\n• Backup: Save /root directory\n• Restore: Recover saved data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Rootfs Management")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.refresh()
            importModel.refresh()
        }
        .alert("Reset Rootfs?", isPresented: $viewModel.showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                viewModel.resetRootfs(keepUserData: false)
            }
        } message: {
            Text("This will delete the entire rootfs. All data will be lost. The app will need to restart to reinstall.")
        }
        .alert("Reset with Backup?", isPresented: $viewModel.showResetWithBackupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset & Backup", role: .destructive) {
                viewModel.resetRootfs(keepUserData: true)
            }
        } message: {
            Text("This will backup your /root directory, then reset the rootfs. You can restore the backup later.")
        }
        .sheet(isPresented: $showFileBrowser) {
            NavigationStack {
                FileBrowserView(rootPath: RootfsManager.shared.dataPath, rootLabel: "/")
            }
        }
        .sheet(isPresented: $importModel.presentPicker) {
            RootfsDocumentPicker { url in
                importModel.startImport(of: url)
            }
            .ignoresSafeArea()
        }
        .onChange(of: importModel.requestRelaunch) { _, needsRelaunch in
            guard needsRelaunch else { return }
            viewModel.refresh()
        }
    }
}

// MARK: - Reusable section: import any rootfs.tar.gz and manage profiles.
// Rendered inside RootfsManagementView's List as a dedicated menu section.

struct RootfsImportSection: View {
    @ObservedObject var model: RootfsImportViewModel

    var body: some View {
        Section("Distributions") {
            Text("Import any mini-rootfs tarball (.tar.gz / .tgz / .tar / .tar.xz) to add another Linux distribution, or switch between installed ones.")
                .font(.caption)
                .foregroundColor(.secondary)

            if model.profiles.isEmpty {
                Text("No imported rootfs yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(model.profiles, id: \.self) { name in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .fontWeight(model.active == name ? .semibold : .regular)
                            if model.active == name {
                                Text("Active — booted on next launch")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                        Spacer()
                        if model.active == name {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Load") {
                                model.switchProfile(to: name)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                        if name != "alpine-rootfs" && model.active != name {
                            Button(role: .destructive) {
                                model.deleteProfile(name)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Button {
                model.presentPicker = true
            } label: {
                Label {
                    Text(model.isImporting ? "Importing…" : "Import rootfs (tar.gz)")
                } icon: {
                    Image(systemName: model.isImporting ? "arrow.triangle.2.circlepath" : "square.and.arrow.down")
                }
            }
            .disabled(model.isImporting)

            if model.isImporting {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.importStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let message = model.message {
                Text(message.text)
                    .font(.callout)
                    .foregroundColor(message.isError ? .red : .green)
            }
        }
    }
}

class RootfsManagementViewModel: ObservableObject {
    @Published var isInstalled = false
    @Published var isProcessing = false
    @Published var statusMessage = ""
    @Published var resultMessage: String?
    @Published var lastOperationSuccess = false
    @Published var rootfsSize: Int64 = 0
    @Published var hasBackup = false
    @Published var showResetConfirmation = false
    @Published var showResetWithBackupConfirmation = false

    private var backupURL: URL?

    var rootfsPath: String {
        RootfsManager.shared.rootfsPath.path
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: rootfsSize, countStyle: .file)
    }

    func refresh() {
        isInstalled = RootfsManager.shared.isInstalled

        if isInstalled {
            DispatchQueue.global(qos: .utility).async {
                do {
                    let size = try RootfsManager.shared.getRootfsSize()
                    DispatchQueue.main.async {
                        self.rootfsSize = size
                    }
                } catch {
                    print("Failed to get rootfs size: \(error)")
                }
            }
        }
    }

    func install() {
        isProcessing = true
        statusMessage = "Installing rootfs..."
        resultMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try RootfsManager.shared.installIfNeeded()

                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.lastOperationSuccess = true
                    self.resultMessage = "✅ Rootfs installed successfully"
                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.lastOperationSuccess = false
                    self.resultMessage = "❌ Installation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func resetRootfs(keepUserData: Bool) {
        isProcessing = true
        statusMessage = keepUserData ? "Backing up and resetting..." : "Resetting rootfs..."
        resultMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let backup = try RootfsManager.shared.reset(keepUserData: keepUserData)

                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.lastOperationSuccess = true
                    self.backupURL = backup
                    self.hasBackup = backup != nil

                    if keepUserData {
                        self.resultMessage = "✅ Rootfs reset with backup created"
                    } else {
                        self.resultMessage = "✅ Rootfs reset complete. Restart app to reinstall."
                    }

                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.lastOperationSuccess = false
                    self.resultMessage = "❌ Reset failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func restoreBackup() {
        guard let backupURL = backupURL else {
            resultMessage = "❌ No backup available"
            return
        }

        isProcessing = true
        statusMessage = "Restoring user data..."
        resultMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try RootfsManager.shared.restoreUserData(from: backupURL)

                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.lastOperationSuccess = true
                    self.resultMessage = "✅ User data restored successfully"
                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.lastOperationSuccess = false
                    self.resultMessage = "❌ Restore failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RootfsManagementView()
    }
}
