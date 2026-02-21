import SwiftUI
import SwiftData

@main
struct RunTrackerApp: App {
    @StateObject private var authManager = AuthenticationManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    ContentView()
                } else {
                    SignInView()
                }
            }
            .environmentObject(authManager)
            .onAppear {
                authManager.checkCredentialState()
            }
        }
        .modelContainer(for: [Run.self, UserProfile.self, CoachingResponse.self])
    }
}
