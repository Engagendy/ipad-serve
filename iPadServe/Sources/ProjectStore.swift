import CryptoKit
import Foundation
import UIKit
import UniformTypeIdentifiers

struct PendingImport {
    let stagedURL: URL
    let name: String
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ProjectItem] = []
    @Published private(set) var favoriteNames: Set<String> = []
    @Published private(set) var defaultProjectName: String?
    @Published private(set) var lastOpenedPages: [String: String] = [:]
    @Published var importError: String?
    @Published var pendingImport: PendingImport?

    private let fileManager = FileManager.default
    private let favoritesKey = "favoriteProjectNames"
    private let defaultProjectKey = "defaultProjectName"
    private let lastOpenedPagesKey = "lastOpenedPages"
    private let linkedBookmarksKey = "linkedProjectBookmarks"
    private var accessedLinkedURLs: [String: URL] = [:]
    private let bundledSampleName = "HTML Serve Guide"
    private let bundledSampleInstallKey = "didInstallBundledSampleProject.v5"
    private let bundledSampleFiles = [
        "index.html",
        "styles.css",
        "app.js",
        "screenshots/01-projects.png",
        "screenshots/02-file-browser.png",
        "screenshots/03-running-guide.png"
    ]

    var projectsDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Projects", isDirectory: true)
    }

    func loadProjects() {
        try? fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        installBundledSampleIfNeeded()

        favoriteNames = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        defaultProjectName = UserDefaults.standard.string(forKey: defaultProjectKey)
        lastOpenedPages = (UserDefaults.standard.dictionary(forKey: lastOpenedPagesKey) as? [String: String]) ?? [:]

        let folders = (try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let copiedProjects = folders.compactMap { url -> ProjectItem? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return ProjectItem(id: stableID(for: url), name: url.lastPathComponent, rootURL: url)
        }

        projects = (copiedProjects + linkedProjects())
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        updateHomeScreenQuickActions()
    }

    private func linkedBookmarks() -> [String: Data] {
        (UserDefaults.standard.dictionary(forKey: linkedBookmarksKey) as? [String: Data]) ?? [:]
    }

    private func linkedProjects() -> [ProjectItem] {
        var bookmarks = linkedBookmarks()
        var didUpdateBookmarks = false

        let items = bookmarks.compactMap { name, bookmark -> ProjectItem? in
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
                return nil
            }

            if accessedLinkedURLs[name] == nil, url.startAccessingSecurityScopedResource() {
                accessedLinkedURLs[name] = url
            }

            if isStale, let fresh = try? url.bookmarkData() {
                bookmarks[name] = fresh
                didUpdateBookmarks = true
            }

            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return ProjectItem(id: stableID(for: url), name: name, rootURL: url, isLinked: true)
        }

        if didUpdateBookmarks {
            UserDefaults.standard.set(bookmarks, forKey: linkedBookmarksKey)
        }

        return items
    }

    /// Links a folder in place with a security-scoped bookmark instead of
    /// copying it into the app, so large books don't use storage twice.
    func linkFolder(from sourceURL: URL) {
        importError = nil
        guard sourceURL.startAccessingSecurityScopedResource() else {
            importError = String(localized: "The folder could not be imported.")
            return
        }

        let rawName = sourceURL.deletingPathExtension().lastPathComponent
        let name = rawName.isEmpty ? "Project" : rawName

        guard !projects.contains(where: { $0.name == name }) else {
            sourceURL.stopAccessingSecurityScopedResource()
            importError = String(localized: "A project named \"\(name)\" already exists.")
            return
        }

        do {
            let bookmark = try sourceURL.bookmarkData()
            var bookmarks = linkedBookmarks()
            bookmarks[name] = bookmark
            UserDefaults.standard.set(bookmarks, forKey: linkedBookmarksKey)
            accessedLinkedURLs[name] = sourceURL
            loadProjects()
        } catch {
            sourceURL.stopAccessingSecurityScopedResource()
            importError = error.localizedDescription
        }
    }

    func rename(_ project: ProjectItem, to rawNewName: String) {
        importError = nil
        let newName = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != project.name, !project.isLinked else { return }

        guard !newName.contains("/"), !newName.hasPrefix(".") else {
            importError = String(localized: "This name cannot be used.")
            return
        }

        guard !projects.contains(where: { $0.name == newName }) else {
            importError = String(localized: "A project named \"\(newName)\" already exists.")
            return
        }

        do {
            let destination = projectsDirectory.appendingPathComponent(newName, isDirectory: true)
            try fileManager.moveItem(at: project.rootURL, to: destination)
            migratePreferences(from: project.name, to: newName)
            loadProjects()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func migratePreferences(from oldName: String, to newName: String) {
        if favoriteNames.remove(oldName) != nil {
            favoriteNames.insert(newName)
            UserDefaults.standard.set(Array(favoriteNames).sorted(), forKey: favoritesKey)
        }
        if defaultProjectName == oldName {
            defaultProjectName = newName
            UserDefaults.standard.set(newName, forKey: defaultProjectKey)
        }
        if let page = lastOpenedPages.removeValue(forKey: oldName) {
            lastOpenedPages[newName] = page
            UserDefaults.standard.set(lastOpenedPages, forKey: lastOpenedPagesKey)
        }
    }

    var favoriteProjects: [ProjectItem] {
        projects.filter { favoriteNames.contains($0.name) }
    }

    var otherProjects: [ProjectItem] {
        projects.filter { !favoriteNames.contains($0.name) }
    }

    var defaultProject: ProjectItem? {
        guard let defaultProjectName else { return nil }
        return projects.first { $0.name == defaultProjectName }
    }

    func project(named name: String) -> ProjectItem? {
        projects.first { $0.name == name }
    }

    func isFavorite(_ project: ProjectItem) -> Bool {
        favoriteNames.contains(project.name)
    }

    func toggleFavorite(_ project: ProjectItem) {
        if favoriteNames.contains(project.name) {
            favoriteNames.remove(project.name)
        } else {
            favoriteNames.insert(project.name)
        }
        UserDefaults.standard.set(Array(favoriteNames).sorted(), forKey: favoritesKey)
        updateHomeScreenQuickActions()
    }

    /// The page to open when running a project: the last page the user viewed,
    /// falling back to index.html / the first HTML page.
    func entryPage(for project: ProjectItem) -> ProjectFile? {
        if let relativePath = lastOpenedPages[project.name],
           let file = project.htmlFiles.first(where: { $0.relativePath == relativePath }) {
            return file
        }
        return project.preferredEntry
    }

    func recordLastOpened(_ file: ProjectFile, in project: ProjectItem) {
        let ext = file.url.pathExtension.lowercased()
        guard ext == "html" || ext == "htm" else { return }
        lastOpenedPages[project.name] = file.relativePath
        UserDefaults.standard.set(lastOpenedPages, forKey: lastOpenedPagesKey)
    }

    func isDefault(_ project: ProjectItem) -> Bool {
        project.name == defaultProjectName
    }

    func setDefault(_ project: ProjectItem?) {
        defaultProjectName = project?.name
        UserDefaults.standard.set(defaultProjectName, forKey: defaultProjectKey)
    }

    /// Long-pressing the app icon offers the favorite projects (iOS shows at most 4).
    private func updateHomeScreenQuickActions() {
        let items = favoriteProjects.prefix(4).map { project in
            UIApplicationShortcutItem(
                type: LaunchRouter.quickActionType,
                localizedTitle: project.name,
                localizedSubtitle: String(localized: "Open project"),
                icon: UIApplicationShortcutIcon(systemImageName: "play.rectangle"),
                userInfo: [LaunchRouter.quickActionProjectKey: project.name as NSString]
            )
        }
        UIApplication.shared.shortcutItems = Array(items)
    }

    func importFolder(from sourceURL: URL) {
        importError = nil
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
            let rawName = sourceURL.deletingPathExtension().lastPathComponent
            let name = rawName.isEmpty ? "Project" : rawName
            // Copy into a staging folder first so a name collision can be
            // resolved (replace/keep both) without touching the existing project.
            let staging = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try copyDirectory(from: sourceURL, to: staging)

            if projects.first(where: { $0.name == name })?.isLinked == true {
                try? fileManager.removeItem(at: staging)
                importError = String(localized: "A project named \"\(name)\" already exists.")
                return
            }

            let destination = projectsDirectory.appendingPathComponent(name, isDirectory: true)
            if fileManager.fileExists(atPath: destination.path) {
                pendingImport = PendingImport(stagedURL: staging, name: name)
            } else {
                try fileManager.moveItem(at: staging, to: destination)
                loadProjects()
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    func resolvePendingImport(replacing: Bool) {
        guard let pending = pendingImport else { return }
        pendingImport = nil

        do {
            let destination: URL
            if replacing {
                destination = projectsDirectory.appendingPathComponent(pending.name, isDirectory: true)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
            } else {
                destination = uniqueDestination(for: pending.name)
            }
            try fileManager.moveItem(at: pending.stagedURL, to: destination)
            loadProjects()
        } catch {
            importError = error.localizedDescription
        }
    }

    func cancelPendingImport() {
        guard let pending = pendingImport else { return }
        pendingImport = nil
        try? fileManager.removeItem(at: pending.stagedURL)
    }

    func delete(_ project: ProjectItem) {
        do {
            if project.isLinked {
                var bookmarks = linkedBookmarks()
                bookmarks.removeValue(forKey: project.name)
                UserDefaults.standard.set(bookmarks, forKey: linkedBookmarksKey)
                if let url = accessedLinkedURLs.removeValue(forKey: project.name) {
                    url.stopAccessingSecurityScopedResource()
                }
            } else {
                try fileManager.removeItem(at: project.rootURL)
            }
            if favoriteNames.contains(project.name) {
                favoriteNames.remove(project.name)
                UserDefaults.standard.set(Array(favoriteNames).sorted(), forKey: favoritesKey)
            }
            if defaultProjectName == project.name {
                setDefault(nil)
            }
            if lastOpenedPages.removeValue(forKey: project.name) != nil {
                UserDefaults.standard.set(lastOpenedPages, forKey: lastOpenedPagesKey)
            }
            loadProjects()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func installBundledSampleIfNeeded() {
        let destination = projectsDirectory.appendingPathComponent(bundledSampleName, isDirectory: true)
        guard !UserDefaults.standard.bool(forKey: bundledSampleInstallKey) else { return }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            for file in bundledSampleFiles {
                let fileName = (file as NSString).lastPathComponent
                let sourceURL = Bundle.main.url(
                    forResource: (fileName as NSString).deletingPathExtension,
                    withExtension: (fileName as NSString).pathExtension
                )
                guard let sourceURL else { continue }
                let targetURL = destination.appendingPathComponent(file)
                try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: sourceURL, to: targetURL)
            }
            UserDefaults.standard.set(true, forKey: bundledSampleInstallKey)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func uniqueDestination(for rawName: String) -> URL {
        let baseName = rawName.isEmpty ? "Project" : rawName
        var candidate = projectsDirectory.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = projectsDirectory.appendingPathComponent("\(baseName) \(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidate
    }

    private func copyDirectory(from source: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return
        }

        for case let itemURL as URL in enumerator {
            let relative = FileScanner.relativePath(for: itemURL, root: source)
            guard !relative.isEmpty else { continue }
            let target = destination.appendingPathComponent(relative)
            let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey])

            if values.isDirectory == true {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.copyItem(at: itemURL, to: target)
            }
        }
    }

    private func stableID(for url: URL) -> UUID {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
