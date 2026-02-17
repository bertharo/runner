import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @AppStorage("use_miles") private var useMiles = true

    @StateObject private var stravaAuth = StravaAuth()
    @State private var stravaClient: StravaClient?

    @State private var goalRace = ""
    @State private var goalDate = ""
    @State private var goalTime = ""
    @State private var weeklyMileageTarget = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Distance", selection: $useMiles) {
                        Text("Miles").tag(true)
                        Text("Kilometers").tag(false)
                    }
                }

                Section("Strava") {
                    if stravaAuth.isAuthenticated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Connected")
                        }

                        Button("Sync Activities") {
                            let client = getStravaClient()
                            Task { await client.syncActivities(modelContext: modelContext) }
                        }
                        .disabled(getStravaClient().isSyncing)

                        if let status = getStravaClient().syncStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button("Disconnect", role: .destructive) {
                            stravaAuth.disconnect()
                        }
                    } else {
                        Button("Connect Strava") {
                            stravaAuth.authorize()
                        }
                    }

                    if let error = stravaAuth.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Goal Race") {
                    TextField("Race Name (e.g. Boston Marathon)", text: $goalRace)
                    TextField("Date (e.g. 2026-04-20)", text: $goalDate)
                    TextField("Target Time (e.g. 3:30:00)", text: $goalTime)
                    TextField("Weekly Mileage Target", text: $weeklyMileageTarget)
                        .keyboardType(.decimalPad)

                    Button("Save Goal") {
                        saveGoal()
                    }
                    .disabled(goalRace.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Settings")
            .onAppear { loadProfile() }
        }
    }

    private func getStravaClient() -> StravaClient {
        if let client = stravaClient { return client }
        let client = StravaClient(auth: stravaAuth)
        stravaClient = client
        return client
    }

    private func loadProfile() {
        guard let profile = profiles.first else { return }
        goalRace = profile.goalRace
        goalDate = profile.goalDate ?? ""
        goalTime = profile.goalTime ?? ""
        weeklyMileageTarget = profile.weeklyMileageTarget.map { String($0) } ?? ""
    }

    private func saveGoal() {
        let target = Double(weeklyMileageTarget)

        if let existing = profiles.first {
            existing.goalRace = goalRace
            existing.goalDate = goalDate.isEmpty ? nil : goalDate
            existing.goalTime = goalTime.isEmpty ? nil : goalTime
            existing.weeklyMileageTarget = target
        } else {
            let profile = UserProfile(
                goalRace: goalRace,
                goalDate: goalDate.isEmpty ? nil : goalDate,
                goalTime: goalTime.isEmpty ? nil : goalTime,
                weeklyMileageTarget: target
            )
            modelContext.insert(profile)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Run.self, UserProfile.self, CoachingResponse.self], inMemory: true)
}
