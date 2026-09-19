import SwiftUI
import UniformTypeIdentifiers

struct ProjectDetailView: View {
    @EnvironmentObject private var server: LocalHTTPServer
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.scenePhase) private var scenePhase
    let project: ProjectItem
    var autoRun = false
    var onAutoRunConsumed: () -> Void = {}
    var goHome: () -> Void = {}
    @State private var selectedPage: BrowserPage?
    @State private var isRelinking = false
    @State private var browserItems: [ProjectBrowserItem] = []
    @State private var hasLoadedItems = false
    @State private var isSharePresented = false
    @State private var shareFile: ProjectFile?
    @State private var exportedArchive: ExportedArchive?
    @StateObject private var watcher = ProjectWatcher()
    @State private var autoReload = false
    @State private var reloadToken = 0
    @State private var fileSearchText = ""

    var body: some View {
        Group {
            if project.isBroken {
                ContentUnavailableView {
                    Label("Folder Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The linked folder could not be found. It may have been moved, renamed, or deleted. Re-link it to keep this project's favorite and launch settings.")
                } actions: {
                    Button {
                        isRelinking = true
                    } label: {
                        Label("Re-link Folder…", systemImage: "link.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .fileImporter(
                    isPresented: $isRelinking,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    guard case let .success(urls) = result, let url = urls.first else { return }
                    store.relinkFolder(for: project, to: url)
                }
            } else if let selectedPage {
                BrowserView(
                    page: selectedPage,
                    close: { self.selectedPage = nil },
                    goHome: {
                        self.selectedPage = nil
                        goHome()
                    },
                    share: { currentURL in
                        shareFile = projectFile(forServedURL: currentURL)
                        isSharePresented = true
                    },
                    reloadToken: reloadToken,
                    autoReload: $autoReload
                )
            } else {
                List {
                    if fileSearchQuery.isEmpty {
                        Section {
                            OutlineGroup(browserItems, children: \.outlineChildren) { item in
                                ProjectBrowserRow(
                                    item: item,
                                    open: {
                                        Task { await open(item) }
                                    },
                                    share: item.kind == .html ? {
                                        shareFile = item.projectFile
                                        isSharePresented = true
                                    } : nil
                                )
                            }
                        } header: {
                            Text("Files")
                        }
                    } else {
                        // Search flattens the whole tree so matches deep in
                        // subfolders show up with their relative paths.
                        Section {
                            ForEach(searchResults) { item in
                                ProjectBrowserRow(
                                    item: item,
                                    open: {
                                        Task { await open(item) }
                                    },
                                    share: item.kind == .html ? {
                                        shareFile = item.projectFile
                                        isSharePresented = true
                                    } : nil
                                )
                            }
                        } header: {
                            Text("Matching Files")
                        }
                    }
                }
                .searchable(text: $fileSearchText, prompt: Text("Search files"))
                .overlay {
                    if !fileSearchQuery.isEmpty, searchResults.isEmpty {
                        ContentUnavailableView.search(text: fileSearchQuery)
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
        // Applied unconditionally, with values that vary, rather than from
        // inside the branches above. Adding and removing these modifiers as
        // the branch changes hands the navigation controller a different
        // navigation item mid-flight, which is what UIKit asserts on when the
        // split view re-parents this column.
        .navigationTitle(project.name)
        .toolbar(isShowingPage ? .hidden : .visible, for: .navigationBar)
        .navigationBarBackButtonHidden(isShowingPage)
        .toolbar {
            if showsFileToolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ImportMenu()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        shareFile = nil
                        isSharePresented = true
                    } label: {
                        Label("Share QR Code", systemImage: "qrcode")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportProject()
                    } label: {
                        Label("Export Project", systemImage: "square.and.arrow.up")
                    }
                }
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
        }
        .task(id: autoRun) {
            guard !project.isBroken else { return }
            if !hasLoadedItems {
                browserItems = project.rootBrowserItems
                hasLoadedItems = true
                autoReload = store.isAutoReloadEnabled(project)
            }
            // (Re)start on every appearance: onDisappear stops the watcher
            // and clears its callback, so a returning view must rebuild both.
            watcher.onChange = { handleFilesChanged() }
            watcher.start(watching: project.rootURL)
            try? await server.ensureRunning()
            if autoRun {
                onAutoRunConsumed()
                if let entry = store.entryPage(for: project) {
                    await open(entry)
                }
            }
        }
        .onDisappear {
            watcher.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Close the directory descriptors while backgrounded; linked
                // folders should not stay pinned by open file handles.
                watcher.pause()
            case .active:
                guard hasLoadedItems else { break }
                watcher.resume()
                // Files may have changed while the app was in the background.
                browserItems = FileScanner.browserItems(in: project.rootURL, root: project.rootURL)
            default:
                break
            }
        }
        .onChange(of: autoReload) { _, enabled in
            store.setAutoReload(enabled, for: project)
        }
        .sheet(isPresented: $isSharePresented, onDismiss: { shareFile = nil }) {
            ClassroomShareView(project: project, file: shareFile)
        }
        .sheet(item: $exportedArchive) { archive in
            ActivityShareSheet(items: [archive.url])
        }
    }

    /// True while a page is open in the web view, which draws its own toolbar
    /// and wants the navigation bar out of the way.
    private var isShowingPage: Bool {
        !project.isBroken && selectedPage != nil
    }

    private var showsFileToolbar: Bool {
        !project.isBroken && selectedPage == nil
    }

    private var fileSearchQuery: String {
        fileSearchText.trimmingCharacters(in: .whitespaces)
    }

    /// Files anywhere in the project tree whose name matches the search text,
    /// flattened so each match shows with its relative path.
    private var searchResults: [ProjectBrowserItem] {
        let query = fileSearchQuery
        guard !query.isEmpty else { return [] }
        return flattenedFiles(in: browserItems).filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    private func flattenedFiles(in items: [ProjectBrowserItem]) -> [ProjectBrowserItem] {
        items.flatMap { item in
            item.kind == .folder ? flattenedFiles(in: item.children) : [item]
        }
    }

    /// Runs after the watcher's debounce settles: refreshes the file browser
    /// and bumps the reload token so an open page can live-reload.
    private func handleFilesChanged() {
        browserItems = FileScanner.browserItems(in: project.rootURL, root: project.rootURL)
        reloadToken += 1
    }

    private func exportProject() {
        let project = project
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

    private func open(_ file: ProjectFile) async {
        do {
            try await server.ensureRunning()
        } catch {
            AppNotifier.shared.error(String(localized: "The local server could not start: \(error.localizedDescription)"))
            return
        }

        guard let url = await serverURL(for: file) else {
            AppNotifier.shared.error(String(localized: "The local server is not ready yet. Try opening the page again."))
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

    /// Maps a URL served by LocalHTTPServer (/file/<root>/<path>) back to the
    /// project file it represents, so the browser can share the open page.
    private func projectFile(forServedURL url: URL?) -> ProjectFile? {
        guard let url else { return nil }
        let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 3, components[0] == "file" else { return nil }
        let relativePath = components.dropFirst(2).map(String.init).joined(separator: "/")
        guard let name = relativePath.split(separator: "/").last.map(String.init) else { return nil }
        return ProjectFile(
            name: name,
            relativePath: relativePath,
            url: project.rootURL.appendingPathComponent(relativePath)
        )
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
    var share: (() -> Void)? = nil

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
            .contextMenu {
                if let share {
                    Button {
                        share()
                    } label: {
                        Label("Share This Page", systemImage: "qrcode")
                    }
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
