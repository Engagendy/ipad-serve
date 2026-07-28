import AppIntents
import Foundation

/// Lets users run "Open Project" from the Shortcuts app and place a shortcut
/// to a specific project on the Home Screen.
struct OpenProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Project"
    static var description = IntentDescription("Opens a project in HTML Serve.")
    static var openAppWhenRun = true

    @Parameter(title: "Project", optionsProvider: ProjectNameOptionsProvider())
    var projectName: String

    @MainActor
    func perform() async throws -> some IntentResult {
        LaunchRouter.shared.requestOpen(projectNamed: projectName)
        return .result()
    }
}

struct ProjectNameOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectsDirectory = documents.appendingPathComponent("Projects", isDirectory: true)
        let folders = (try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

struct HTMLServeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenProjectIntent(),
            phrases: ["Open a project in \(.applicationName)"],
            shortTitle: "Open Project",
            systemImageName: "play.rectangle"
        )
    }
}
