import SwiftUI
import UIKit

/// Routes external open requests (Home Screen quick actions, htmlserve:// links,
/// Shortcuts app intents) to the project list. ContentView observes
/// `pendingProjectName` and opens the matching project.
@MainActor
final class LaunchRouter: ObservableObject {
    static let shared = LaunchRouter()

    static let quickActionType = "com.engagendy.iPadServe.openProject"
    static let quickActionProjectKey = "projectName"

    @Published var pendingProjectName: String?

    func requestOpen(projectNamed name: String) {
        pendingProjectName = name
    }

    func handle(shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard shortcutItem.type == Self.quickActionType,
              let name = shortcutItem.userInfo?[Self.quickActionProjectKey] as? String else {
            return false
        }
        requestOpen(projectNamed: name)
        return true
    }

    /// Supports htmlserve://open?project=<name> and htmlserve://project/<name>.
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "htmlserve" else { return }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let name = components.queryItems?.first(where: { $0.name == "project" })?.value,
           !name.isEmpty {
            requestOpen(projectNamed: name)
            return
        }

        let pathName = url.pathComponents.filter { $0 != "/" }.joined(separator: "/")
        if !pathName.isEmpty {
            requestOpen(projectNamed: pathName)
        } else if let host = url.host, host.lowercased() != "open" {
            requestOpen(projectNamed: host)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcutItem = connectionOptions.shortcutItem {
            Task { @MainActor in
                _ = LaunchRouter.shared.handle(shortcutItem: shortcutItem)
            }
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            completionHandler(LaunchRouter.shared.handle(shortcutItem: shortcutItem))
        }
    }
}
