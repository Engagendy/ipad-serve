import SwiftUI

@main
struct iPadServeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Created once for the whole app and shared by every window: the project
    // list and the HTTP server are process-wide (one server port serves all
    // windows), while per-window state (selection, open page, search) lives
    // in each scene's ContentView.
    @StateObject private var store = ProjectStore()
    @StateObject private var server = LocalHTTPServer()
    @StateObject private var router = LaunchRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(server)
                .environmentObject(router)
                .task {
                    store.loadProjects()
                    try? await server.ensureRunning()
                }
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }

        // Value-based scene backing "Open in New Window": openWindow(value:)
        // with a project name lands here in a fresh window.
        WindowGroup(for: String.self) { $projectName in
            ContentView(initialProjectName: projectName)
                .environmentObject(store)
                .environmentObject(server)
                .environmentObject(router)
                .task {
                    try? await server.ensureRunning()
                }
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }
    }
}
