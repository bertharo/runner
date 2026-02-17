import SwiftUI
import SwiftData

struct RunListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]
    @State private var showingAddRun = false

    private var totalDistance: Double {
        runs.reduce(0) { $0 + $1.distance }
    }

    private var averagePace: Double {
        let totalDuration = runs.reduce(0) { $0 + $1.duration }
        guard totalDistance > 0 else { return 0 }
        return (Double(totalDuration) / 60.0) / totalDistance
    }

    var body: some View {
        NavigationStack {
            List {
                if !runs.isEmpty {
                    Section("Summary") {
                        HStack {
                            StatCard(title: "Runs", value: "\(runs.count)")
                            StatCard(title: "Distance", value: PaceFormatter.formattedDistance(km: totalDistance))
                            StatCard(title: "Avg Pace", value: PaceFormatter.formatted(pace: averagePace))
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                Section(runs.isEmpty ? "" : "History") {
                    if runs.isEmpty {
                        ContentUnavailableView(
                            "No Runs Yet",
                            systemImage: "figure.run",
                            description: Text("Tap + to log your first run.")
                        )
                    } else {
                        ForEach(runs) { run in
                            NavigationLink(destination: RunDetailView(run: run)) {
                                RunRow(run: run)
                            }
                        }
                        .onDelete(perform: deleteRuns)
                    }
                }
            }
            .navigationTitle("tränare")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddRun = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddRun) {
                AddRunView()
            }
        }
    }

    private func deleteRuns(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(runs[index])
        }
    }
}

struct RunRow: View {
    let run: Run

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(run.date, style: .date)
                .font(.headline)
            HStack(spacing: 16) {
                Label(PaceFormatter.formattedDistance(km: run.distance), systemImage: "map")
                Label(PaceFormatter.formattedDuration(seconds: run.duration), systemImage: "clock")
                Label(PaceFormatter.formatted(pace: run.pace), systemImage: "speedometer")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    RunListView()
        .modelContainer(for: Run.self, inMemory: true)
}
