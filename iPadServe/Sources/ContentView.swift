import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var server: LocalHTTPServer
    @EnvironmentObject private var router: LaunchRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedProject: ProjectItem?
    @State private var isImporting = false
    @State private var importAsLink = false
    @State private var renameTarget: ProjectItem?
    @State private var renameText = ""
    @State private var shareTarget: ProjectItem?
    @State private var autoRunProjectID: UUID?
    @State private var hasAppliedLaunchDefault = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var searchText = ""

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
                    Menu {
                        Button {
                            importAsLink = false
                            isImporting = true
                        } label: {
                            Label("Copy Folder into App", systemImage: "folder.badge.plus")
                        }
                        Button {
                            importAsLink = true
                            isImporting = true
                        } label: {
                            Label("Link Folder in Place", systemImage: "link.badge.plus")
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
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            if importAsLink {
                store.linkFolder(from: url)
            } else {
                store.importFolder(from: url)
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
        .alert("Import Failed", isPresented: Binding(
            get: { store.importError != nil },
            set: { if !$0 { store.importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.importError ?? "The folder could not be imported.")
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
            try? await server.ensureRunning()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                try? await server.ensureRunning()
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
            ClassroomShareView(
                projectName: project.name,
                url: store.entryPage(for: project).flatMap { server.lanURL(for: project, file: $0) }
            )
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
            NavigationLink(value: project) {
                ProjectRow(
                    project: project,
                    isFavorite: store.isFavorite(project),
                    isDefault: store.isDefault(project)
                )
            }
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
                if !project.isLinked {
                    Button {
                        renameText = project.name
                        renameTarget = project
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                }
                if server.allowsLAN {
                    Button {
                        shareTarget = project
                    } label: {
                        Label("Classroom QR Code", systemImage: "qrcode")
                    }
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
            return !store.projects.isEmpty ? consumePendingRoute() : false
        }
        hasAppliedLaunchDefault = true
        selectedProject = project
        autoRunProjectID = project.id
        return consumePendingRoute()
    }

    private func consumePendingRoute() -> Bool {
        router.pendingProjectName = nil
        return true
    }
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
                Text("\(project.htmlFiles.count) HTML pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if project.isLinked {
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
