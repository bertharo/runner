import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RunListView()
                .tabItem {
                    Label("Runs", systemImage: "figure.run")
                }

            CoachView()
                .tabItem {
                    Label("Coach", systemImage: "brain.head.profile")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Run.self, UserProfile.self, CoachingResponse.self], inMemory: true)
}
