import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @EnvironmentObject private var authManager: AuthenticationManager

    @AppStorage("use_miles") private var useMiles = true
    @AppStorage("coach_model") private var coachModel = "llama-3.3-70b-versatile"

    @StateObject private var stravaAuth = StravaAuth()
    @State private var showSignOutConfirmation = false
    @State private var stravaClient: StravaClient?

    @State private var goalRace = ""
    @State private var goalDate = ""
    @State private var goalTime = ""
    @State private var weeklyMileageTarget = ""
    @State private var goalSaved = false
    @FocusState private var mileageFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let email = authManager.userEmail {
                        LabeledContent("Email", value: email)
                    }

                    Button("Sign Out", role: .destructive) {
                        showSignOutConfirmation = true
                    }
                }

                Section("Units") {
                    Picker("Distance", selection: $useMiles) {
                        Text("Miles").tag(true)
                        Text("Kilometers").tag(false)
                    }
                }

                Section("AI Coach") {
                    Picker("Model", selection: $coachModel) {
                        Section("Free") {
                            Text("Llama 3.3 70B").tag("llama-3.3-70b-versatile")
                        }
                        Section("Premium") {
                            Text("Haiku (Fast)").tag("claude-haiku-4-5-20251001")
                            Text("Sonnet (Balanced)").tag("claude-sonnet-4-5-20250929")
                            Text("Opus (Most Capable)").tag("claude-opus-4-6")
                        }
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
                        .focused($mileageFieldFocused)

                    Button("Save Goal") {
                        saveGoal()
                        goalSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            goalSaved = false
                        }
                    }
                    .disabled(goalRace.trimmingCharacters(in: .whitespaces).isEmpty)

                    if goalSaved {
                        Text("Goal saved!")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        mileageFieldFocused = false
                    }
                }
            }
            .onAppear { loadProfile() }
            .alert("Sign Out", isPresented: $showSignOutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    authManager.signOut()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to sign out?")
            }
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
        .environmentObject(AuthenticationManager.shared)
        .modelContainer(for: [Run.self, UserProfile.self, CoachingResponse.self], inMemory: true)
}
