import SwiftUI
import SwiftData

@main
struct RunTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Run.self, UserProfile.self, CoachingResponse.self])
    }
}
