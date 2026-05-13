import Foundation

enum FileScanner {
    static func browserItems(in directory: URL, root: URL) -> [ProjectBrowserItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            let relative = relativePath(for: url, root: root)

            if values?.isDirectory == true {
                return ProjectBrowserItem(
                    name: url.lastPathComponent,
                    relativePath: relative,
                    url: url,
                    kind: .folder,
                    children: browserItems(in: url, root: root)
                )
            }

            guard values?.isRegularFile == true else { return nil }
            return ProjectBrowserItem(
                name: url.lastPathComponent,
                relativePath: relative,
                url: url,
                kind: isHTML(url) ? .html : .file,
                children: []
            )
        }
        .sorted(by: sortBrowserItems)
    }

    static func htmlFiles(in rootURL: URL) -> [ProjectFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            guard isHTML(url) else { return nil }
            let relative = relativePath(for: url, root: rootURL)
            return ProjectFile(name: url.lastPathComponent, relativePath: relative, url: url)
        }
        .sorted { lhs, rhs in
            if lhs.relativePath.lowercased() == "index.html" { return true }
            if rhs.relativePath.lowercased() == "index.html" { return false }
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
    }

    static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func isHTML(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "html" || url.pathExtension.lowercased() == "htm"
    }

    private static func sortBrowserItems(_ lhs: ProjectBrowserItem, _ rhs: ProjectBrowserItem) -> Bool {
        if lhs.kind == .folder, rhs.kind != .folder { return true }
        if lhs.kind != .folder, rhs.kind == .folder { return false }
        if lhs.relativePath.lowercased() == "index.html" { return true }
        if rhs.relativePath.lowercased() == "index.html" { return false }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
