import SwiftUI

@main
struct iPadServeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
    }
}
