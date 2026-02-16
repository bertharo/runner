import SwiftUI
import SwiftData

struct RunDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let run: Run
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            Section("Run Details") {
                DetailRow(icon: "calendar", label: "Date", value: run.date.formatted(date: .long, time: .omitted))
                DetailRow(icon: "map", label: "Distance", value: PaceFormatter.formattedDistance(km: run.distance))
                DetailRow(icon: "clock", label: "Duration", value: PaceFormatter.formattedDuration(seconds: run.duration))
                DetailRow(icon: "speedometer", label: "Pace", value: PaceFormatter.formatted(pace: run.pace))
            }

            if run.syncedFromStrava {
                Section("Strava Data") {
                    if let name = run.name {
                        DetailRow(icon: "text.quote", label: "Name", value: name)
                    }
                    if let hr = run.averageHeartrate {
                        DetailRow(icon: "heart.fill", label: "Avg HR", value: "\(Int(hr)) bpm")
                    }
                    if let maxHr = run.maxHeartrate {
                        DetailRow(icon: "heart", label: "Max HR", value: "\(Int(maxHr)) bpm")
                    }
                    if let elev = run.totalElevationGain {
                        DetailRow(icon: "mountain.2", label: "Elevation", value: String(format: "%.0f m", elev))
                    }
                    if let suffer = run.sufferScore {
                        DetailRow(icon: "flame", label: "Suffer Score", value: "\(suffer)")
                    }
                    if let wt = run.workoutType {
                        let label = switch wt {
                        case 1: "Race"
                        case 2: "Long Run"
                        case 3: "Workout"
                        default: "Default"
                        }
                        DetailRow(icon: "tag", label: "Workout Type", value: label)
                    }
                    if let desc = run.stravaDescription, !desc.isEmpty {
                        Text(desc)
                    }
                }
            }

            if !run.notes.isEmpty {
                Section("Notes") {
                    Text(run.notes)
                }
            }

            Section {
                Button("Delete Run", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Run Details")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this run?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(run)
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        RunDetailView(run: Run(distance: 5.0, duration: 1500, date: .now, notes: "Great run!"))
    }
    .modelContainer(for: Run.self, inMemory: true)
}
