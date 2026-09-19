import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var server: LocalHTTPServer
    @EnvironmentObject private var router: LaunchRouter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    /// Set when this window was opened via "Open in New Window"; selects and
    /// runs that project instead of the launch default.
    var initialProjectName: String?
    @State private var selectedProject: ProjectItem?
    @State private var renameTarget: ProjectItem?
    @State private var renameText = ""
    @State private var shareTarget: ProjectItem?
    @State private var exportedArchive: ExportedArchive?
    @State private var autoRunProjectID: UUID?
    @State private var hasAppliedLaunchDefault = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var searchText = ""
    @State private var relinkTarget: ProjectItem?
    @State private var isRelinkImporterPresented = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedProject) {
                let favorites = filtered(store.favoriteProjects)
                let others = filtered(store.otherProjects)
                if !favorites.isEmpty {
                    Section("Favorites") {
                        projectRows(favorites)
                    }
                }
                Section(favorites.isEmpty ? "" : "Projects") {
                    projectRows(others)
                }
            }
            .searchable(text: $searchText, prompt: "Search projects")
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ImportMenu()
                }
            }
            .refreshable {
                store.loadProjects()
            }
            .overlay {
                if store.projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "folder",
                        description: Text("Import a folder that contains HTML files.")
                    )
                }
            }
        } detail: {
            if let selectedProject {
                ProjectDetailView(
                    project: selectedProject,
                    autoRun: autoRunProjectID == selectedProject.id,
                    onAutoRunConsumed: { autoRunProjectID = nil },
                    goHome: {
                        self.selectedProject = nil
                        columnVisibility = .all
                    }
                )
                .id(selectedProject.id)
            } else {
                ContentUnavailableView("Select a Project", systemImage: "rectangle.stack")
            }
        }
        .confirmationDialog(
            Text("A project named \"\(store.pendingImport?.name ?? "")\" already exists."),
            isPresented: Binding(
                get: { store.pendingImport != nil },
                set: { if !$0 { store.cancelPendingImport() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) {
                store.resolvePendingImport(replacing: true)
            }
            Button("Keep Both") {
                store.resolvePendingImport(replacing: false)
            }
            Button("Cancel", role: .cancel) {
                store.cancelPendingImport()
            }
        } message: {
            Text("Replacing updates the project with the new files and keeps its favorite and launch settings.")
        }
        .fileImporter(
            isPresented: $isRelinkImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            // Read the target here, not from the isPresented binding: the
            // dismissal can flip the binding before this closure runs.
            guard let target = relinkTarget else { return }
            relinkTarget = nil
            guard case let .success(urls) = result, let url = urls.first else { return }
            store.relinkFolder(for: target, to: url)
        }
        .overlay(alignment: .top) {
            AppNoticeBanner()
                .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            ServerStatusView(
                isRunning: server.isRunning,
                isStarting: server.isStarting,
                port: server.port,
                lanAddress: server.allowsLAN ? LocalHTTPServer.lanIPAddress() : nil
            )
            .padding()
        }
        .task {
            applyInitialProjectIfNeeded()
            await ensureServerRunning()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await ensureServerRunning()
            }
        }
        .onChange(of: store.projects) { _, projects in
            guard !projects.isEmpty else {
                selectedProject = nil
                return
            }

            if applyPendingRoute() { return }

            if !hasAppliedLaunchDefault {
                hasAppliedLaunchDefault = true
                if let name = initialProjectName, let project = store.project(named: name) {
                    selectedProject = project
                    autoRunProjectID = project.id
                    return
                }
                if let defaultProject = store.defaultProject {
                    selectedProject = defaultProject
                    autoRunProjectID = defaultProject.id
                    return
                }
            }

            if let selectedID = selectedProject?.id,
               projects.contains(where: { $0.id == selectedID }) {
                return
            }
            selectedProject = projects.first
        }
        .onChange(of: router.pendingProjectName) { _, _ in
            _ = applyPendingRoute()
        }
        .alert("Rename Project", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let target = renameTarget {
                    store.rename(target, to: renameText)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
        }
        .sheet(item: $shareTarget) { project in
            ClassroomShareView(project: project)
        }
        .sheet(item: $exportedArchive) { archive in
            ActivityShareSheet(items: [archive.url])
        }
    }

    private func exportProject(_ project: ProjectItem) {
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try ProjectStore.exportZip(for: project)
                }.value
                exportedArchive = ExportedArchive(url: url)
            } catch {
                AppNotifier.shared.error(String(localized: "The project could not be exported: \(error.localizedDescription)"))
            }
        }
    }

    /// Selects the project a new window was opened for. The store is shared
    /// across windows, so projects are usually loaded already; if not, the
    /// `store.projects` observer applies the same route once they are.
    private func applyInitialProjectIfNeeded() {
        guard !hasAppliedLaunchDefault, let name = initialProjectName,
              let project = store.project(named: name) else { return }
        hasAppliedLaunchDefault = true
        selectedProject = project
        autoRunProjectID = project.id
    }

    private func ensureServerRunning() async {
        do {
            try await server.ensureRunning()
        } catch {
            AppNotifier.shared.error(String(localized: "The local server could not start: \(error.localizedDescription)"))
        }
    }

    private func filtered(_ projects: [ProjectItem]) -> [ProjectItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder
    private func projectRows(_ projects: [ProjectItem]) -> some View {
        ForEach(projects) { project in
            // Plain tagged rows, not NavigationLink: in a NavigationSplitView
            // the List selection is what drives the detail column. A link adds
            // a second, nested navigation container, and when the split view
            // re-parents a column (sidebar toggle, rotation, background
            // snapshot) UIKit asserts in -[UINavigationBar layoutSubviews]
            // that "the top item belongs to a different navigation bar".
            ProjectRow(
                project: project,
                isFavorite: store.isFavorite(project),
                isDefault: store.isDefault(project)
            )
            .tag(project)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    store.toggleFavorite(project)
                } label: {
                    Label(
                        store.isFavorite(project) ? "Unfavorite" : "Favorite",
                        systemImage: store.isFavorite(project) ? "star.slash" : "star"
                    )
                }
                .tint(.yellow)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    store.delete(project)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                if project.isBroken {
                    Button {
                        relinkTarget = project
                        isRelinkImporterPresented = true
                    } label: {
                        Label("Re-link Folder…", systemImage: "link.badge.plus")
                    }
                    Divider()
                }
                if supportsMultipleWindows, !project.isBroken {
                    Button {
                        openWindow(value: project.name)
                    } label: {
                        Label("Open in New Window", systemImage: "rectangle.badge.plus")
                    }
                }
                Button {
                    store.toggleFavorite(project)
                } label: {
                    Label(
                        store.isFavorite(project) ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: store.isFavorite(project) ? "star.slash" : "star"
                    )
                }
                Button {
                    store.setDefault(store.isDefault(project) ? nil : project)
                } label: {
                    Label(
                        store.isDefault(project) ? "Don't Open at Launch" : "Open at Launch",
                        systemImage: store.isDefault(project) ? "bolt.slash" : "bolt"
                    )
                }
                Button {
                    if project.isLinked {
                        // Linked folders keep the name of the folder on disk,
                        // so renaming happens in Files, not here.
                        AppNotifier.shared.info(String(localized: "Linked projects use the folder's own name. Rename the folder in the Files app instead."))
                    } else {
                        renameText = project.name
                        renameTarget = project
                    }
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    shareTarget = project
                } label: {
                    Label("Share QR Code", systemImage: "qrcode")
                }
                Button {
                    exportProject(project)
                } label: {
                    Label("Export Project", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) {
                    store.delete(project)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @discardableResult
    private func applyPendingRoute() -> Bool {
        guard let name = router.pendingProjectName else { return false }
        guard let project = store.project(named: name) else {
            // Keep the request pending if projects haven't loaded yet.
            guard !store.projects.isEmpty else { return false }
            AppNotifier.shared.error(String(localized: "Project \"\(name)\" not found."))
            return consumePendingRoute()
        }
        hasAppliedLaunchDefault = true
        selectedProject = project
        autoRunProjectID = project.id
        return consumePendingRoute()
    }

    private func consumePendingRoute() -> Bool {
        router.consumePendingRoute()
        return true
    }
}

/// Import and sharing controls. Lives in both the sidebar and the project
/// detail toolbars so it stays reachable when the sidebar is collapsed.
struct ImportMenu: View {
    private enum ImportMode {
        case copyFolder
        case linkFolder
        case zipArchive
    }

    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var server: LocalHTTPServer
    @State private var isImporting = false
    @State private var importMode = ImportMode.copyFolder

    var body: some View {
        Menu {
            Button {
                importMode = .copyFolder
                isImporting = true
            } label: {
                Label("Copy Folder into App", systemImage: "folder.badge.plus")
            }
            Button {
                importMode = .linkFolder
                isImporting = true
            } label: {
                Label("Link Folder in Place", systemImage: "link.badge.plus")
            }
            Button {
                importMode = .zipArchive
                isImporting = true
            } label: {
                Label("Import ZIP Archive", systemImage: "doc.zipper")
            }
            Divider()
            Toggle(isOn: Binding(
                get: { server.allowsLAN },
                set: { enabled in Task { await server.setLANSharing(enabled) } }
            )) {
                Label("Share on Local Network", systemImage: "wifi")
            }
        } label: {
            Label("Import Folder", systemImage: "folder.badge.plus")
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: importMode == .zipArchive ? [.zip] : [.folder],
            allowsMultipleSelection: importMode != .zipArchive
        ) { result in
            guard case let .success(urls) = result, !urls.isEmpty else { return }
            switch importMode {
            case .copyFolder:
                store.importFolders(from: urls)
            case .linkFolder:
                for url in urls {
                    store.linkFolder(from: url)
                }
            case .zipArchive:
                if let url = urls.first {
                    store.importZip(from: url)
                }
            }
        }
    }
}

/// Wraps a zipped project so the share sheet can be presented with `.sheet(item:)`.
struct ExportedArchive: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIKit share sheet so an exported zip can be saved via Files or shared.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct ProjectRow: View {
    let project: ProjectItem
    let isFavorite: Bool
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                if project.isBroken {
                    Text("Folder unavailable")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("\(project.htmlFiles.count) HTML pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(project.isBroken ? 0.6 : 1)
            Spacer(minLength: 0)
            if project.isBroken {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Folder unavailable")
            } else if project.isLinked {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Linked folder")
            }
            if isDefault {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Opens at launch")
            }
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ServerStatusView: View {
    let isRunning: Bool
    let isStarting: Bool
    let port: UInt16?
    var lanAddress: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }

    private var iconName: String {
        if isRunning { return "checkmark.circle.fill" }
        if isStarting { return "clock.fill" }
        return "xmark.circle.fill"
    }

    private var iconColor: Color {
        if isRunning { return .green }
        if isStarting { return .orange }
        return .red
    }

    private var statusText: String {
        if isRunning {
            if let lanAddress {
                return String(localized: "Sharing with the classroom on http://\(lanAddress):\(port.map(String.init) ?? "-")")
            }
            return String(localized: "Local server running on 127.0.0.1:\(port.map(String.init) ?? "-")")
        }

        return isStarting
            ? String(localized: "Starting local server...")
            : String(localized: "Server stopped")
    }
}
