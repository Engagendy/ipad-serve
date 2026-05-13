import SwiftUI

@main
struct iPadServeApp: App {
    @StateObject private var store = ProjectStore()
    @StateObject private var server = LocalHTTPServer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(server)
                .task {
                    store.loadProjects()
                    try? await server.start()
                }
        }
    }
}
