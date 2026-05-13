import Foundation

struct ProjectItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rootURL: URL

    var htmlFiles: [ProjectFile] {
        FileScanner.htmlFiles(in: rootURL)
    }

    var rootBrowserItems: [ProjectBrowserItem] {
        FileScanner.browserItems(in: rootURL, root: rootURL)
    }

    var preferredEntry: ProjectFile? {
        htmlFiles.first { $0.relativePath.lowercased() == "index.html" } ?? htmlFiles.first
    }
}

struct ProjectFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let relativePath: String
    let url: URL
}

struct ProjectBrowserItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let relativePath: String
    let url: URL
    let kind: Kind
    let children: [ProjectBrowserItem]

    enum Kind: Hashable {
        case folder
        case html
        case file
    }

    var projectFile: ProjectFile? {
        guard kind == .html || kind == .file else { return nil }
        return ProjectFile(name: name, relativePath: relativePath, url: url)
    }
}
