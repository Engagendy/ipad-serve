import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var server: LocalHTTPServer
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedProject: ProjectItem?
    @State private var isImporting = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProject) {
                ForEach(store.projects) { project in
                    NavigationLink(value: project) {
                        ProjectRow(project: project)
                    }
                }
                .onDelete { offsets in
                    offsets.map { store.projects[$0] }.forEach(store.delete)
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import Folder", systemImage: "folder.badge.plus")
                    }
                }
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
                ProjectDetailView(project: selectedProject)
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
            store.importFolder(from: url)
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
            ServerStatusView(isRunning: server.isRunning, isStarting: server.isStarting, port: server.port)
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
            if let selectedID = selectedProject?.id,
               projects.contains(where: { $0.id == selectedID }) {
                return
            }
            selectedProject = projects.first
        }
    }
}

private struct ProjectRow: View {
    let project: ProjectItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.headline)
            Text("\(project.htmlFiles.count) HTML pages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ServerStatusView: View {
    let isRunning: Bool
    let isStarting: Bool
    let port: UInt16?

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
            return "Local server running on 127.0.0.1:\(port.map(String.init) ?? "-")"
        }

        return isStarting ? "Starting local server..." : "Server stopped"
    }
}
