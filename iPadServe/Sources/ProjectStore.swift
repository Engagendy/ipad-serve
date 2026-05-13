import Foundation
import UniformTypeIdentifiers

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ProjectItem] = []
    @Published var importError: String?

    private let fileManager = FileManager.default
    private let bundledSampleName = "iPad Serve Guide"
    private let bundledSampleInstallKey = "didInstallBundledSampleProject.v2"
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

        let folders = (try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        projects = folders.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return ProjectItem(id: stableID(for: url), name: url.lastPathComponent, rootURL: url)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
            let destination = uniqueDestination(for: sourceURL.deletingPathExtension().lastPathComponent)
            try copyDirectory(from: sourceURL, to: destination)
            loadProjects()
        } catch {
            importError = error.localizedDescription
        }
    }

    func delete(_ project: ProjectItem) {
        do {
            try fileManager.removeItem(at: project.rootURL)
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
        UUID(uuidString: "00000000-0000-0000-0000-\(String(abs(url.path.hashValue)).prefix(12))") ?? UUID()
    }
}
