import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var server: LocalHTTPServer
    @EnvironmentObject private var store: ProjectStore
    let project: ProjectItem
    var autoRun = false
    var onAutoRunConsumed: () -> Void = {}
    var goHome: () -> Void = {}
    @State private var selectedPage: BrowserPage?
    @State private var openError: String?
    @State private var browserItems: [ProjectBrowserItem] = []
    @State private var hasLoadedItems = false

    var body: some View {
        Group {
            if let selectedPage {
                BrowserView(
                    page: selectedPage,
                    close: { self.selectedPage = nil },
                    goHome: {
                        self.selectedPage = nil
                        goHome()
                    }
                )
            } else {
                List {
                    Section {
                        OutlineGroup(browserItems, children: \.outlineChildren) { item in
                            ProjectBrowserRow(item: item) {
                                Task { await open(item) }
                            }
                        }
                    } header: {
                        Text("Files")
                    }
                }
                .navigationTitle(project.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if let entry = store.entryPage(for: project) {
                                Task { await open(entry) }
                            }
                        } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(project.preferredEntry == nil)
                    }
                }
                .overlay {
                    if hasLoadedItems, browserItems.isEmpty {
                        ContentUnavailableView(
                            "No Files",
                            systemImage: "folder.badge.questionmark",
                            description: Text("This folder imported successfully, but no files were found.")
                        )
                    }
                }
            }
        }
        .task(id: autoRun) {
            if !hasLoadedItems {
                browserItems = project.rootBrowserItems
                hasLoadedItems = true
            }
            try? await server.ensureRunning()
            if autoRun {
                onAutoRunConsumed()
                if let entry = store.entryPage(for: project) {
                    await open(entry)
                }
            }
        }
        .alert("Could Not Open Page", isPresented: Binding(
            get: { openError != nil },
            set: { if !$0 { openError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openError ?? "The local server could not open this file.")
        }
    }

    private func open(_ file: ProjectFile) async {
        do {
            try await server.ensureRunning()
        } catch {
            openError = String(localized: "The local server could not start. \(error.localizedDescription)")
            return
        }

        guard let url = await serverURL(for: file) else {
            openError = String(localized: "The local server is not ready yet. Try opening the page again.")
            return
        }

        store.recordLastOpened(file, in: project)
        selectedPage = BrowserPage(title: file.name, url: url)
    }

    private func serverURL(for file: ProjectFile) async -> URL? {
        for _ in 0..<20 {
            if let url = server.url(for: project, file: file) {
                return url
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return nil
    }

    private func open(_ item: ProjectBrowserItem) async {
        guard item.kind != .folder, let file = item.projectFile else { return }
        await open(file)
    }
}

struct BrowserPage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL
}

private struct ProjectBrowserRow: View {
    let item: ProjectBrowserItem
    let open: () -> Void

    var body: some View {
        if item.kind == .folder {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                    Text("\(item.children.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "folder")
                    .foregroundStyle(.blue)
            }
        } else {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .frame(width: 28)
                        .foregroundStyle(iconColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .foregroundStyle(.primary)
                        Text(item.relativePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var iconName: String {
        switch item.kind {
        case .folder:
            return "folder"
        case .html:
            return item.relativePath.lowercased() == "index.html" ? "house" : "safari"
        case .file:
            switch item.url.pathExtension.lowercased() {
            case "mov", "mp4", "m4v", "webm":
                return "play.rectangle"
            case "png", "jpg", "jpeg", "webp", "gif", "svg":
                return "photo"
            case "pdf":
                return "doc.richtext"
            case "js":
                return "curlybraces"
            case "css":
                return "paintbrush"
            default:
                return "doc"
            }
        }
    }

    private var iconColor: Color {
        switch item.kind {
        case .folder:
            return .blue
        case .html:
            return .blue
        case .file:
            return .secondary
        }
    }
}

private extension ProjectBrowserItem {
    var outlineChildren: [ProjectBrowserItem]? {
        kind == .folder ? children : nil
    }
}
