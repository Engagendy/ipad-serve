import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var server: LocalHTTPServer
    let project: ProjectItem
    @State private var selectedPage: BrowserPage?

    var body: some View {
        Group {
            if let selectedPage {
                BrowserView(page: selectedPage) {
                    self.selectedPage = nil
                }
            } else {
                List {
                    Section {
                        OutlineGroup(project.rootBrowserItems, children: \.outlineChildren) { item in
                            ProjectBrowserRow(item: item) {
                                open(item)
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
                            if let entry = project.preferredEntry {
                                open(entry)
                            }
                        } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .disabled(project.preferredEntry == nil || server.port == nil)
                    }
                }
                .overlay {
                    if project.rootBrowserItems.isEmpty {
                        ContentUnavailableView(
                            "No Files",
                            systemImage: "folder.badge.questionmark",
                            description: Text("This folder imported successfully, but no files were found.")
                        )
                    }
                }
            }
        }
        .task {
            if !server.isRunning {
                try? await server.start()
            }
        }
    }

    private func open(_ file: ProjectFile) {
        guard let url = server.url(for: project, file: file) else { return }
        selectedPage = BrowserPage(title: file.name, url: url)
    }

    private func open(_ item: ProjectBrowserItem) {
        guard item.kind != .folder, let file = item.projectFile else { return }
        open(file)
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
