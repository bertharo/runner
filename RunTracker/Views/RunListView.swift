import SwiftUI
import SwiftData

struct RunListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]
    @AppStorage("use_miles") private var useMiles = true
    @AppStorage("week_start_day") private var weekStartDay = 2
    @State private var showingAddRun = false
    @State private var showingCoachSheet = false

    private var unitLabel: String { useMiles ? "mi" : "km" }

    private func dist(_ km: Double) -> Double {
        useMiles ? km * 0.621371 : km
    }

    private func paceForRun(_ run: Run) -> Double {
        let d = dist(run.distance)
        guard d > 0 else { return 0 }
        return (Double(run.movingTime ?? run.duration) / 60.0) / d
    }

    private func formatPace(_ minPerUnit: Double) -> String {
        guard minPerUnit > 0, minPerUnit.isFinite else { return "--:--" }
        let mins = Int(minPerUnit)
        let secs = Int((minPerUnit - Double(mins)) * 60)
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Calendar

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = weekStartDay
        return cal
    }

    private var weekStartDate: Date? {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return calendar.date(from: comps)
    }

    private var weekEndDate: Date? {
        guard let start = weekStartDate else { return nil }
        return calendar.date(byAdding: .day, value: 6, to: start)
    }

    private var weekDateRangeLabel: String {
        guard let start = weekStartDate, let end = weekEndDate else { return "" }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return "\(df.string(from: start)) – \(df.string(from: end))"
    }

    // MARK: - Computed Stats

    private var totalDistance: Double {
        runs.reduce(0) { $0 + dist($1.distance) }
    }

    private var thisWeekDistance: Double {
        guard let start = weekStartDate else { return 0 }
        return runs.filter { $0.date >= start }.reduce(0) { $0 + dist($1.distance) }
    }

    private var thisWeekRuns: Int {
        guard let start = weekStartDate else { return 0 }
        return runs.filter { $0.date >= start }.count
    }

    private var avgPace: Double {
        let valid = runs.prefix(20).filter { $0.distance > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0.0) { $0 + paceForRun($1) } / Double(valid.count)
    }

    private var longestRun: Double {
        runs.map { dist($0.distance) }.max() ?? 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if !runs.isEmpty {
                        if !weekDateRangeLabel.isEmpty {
                            HStack {
                                Text("This Week")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(weekDateRangeLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        kpiGrid
                        runsList
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("tränare")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingCoachSheet = true
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(.purple)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddRun = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddRun) {
                AddRunView()
            }
            .sheet(isPresented: $showingCoachSheet) {
                CoachSheet()
            }
        }
    }

    // MARK: - KPI Grid

    private var kpiGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                KPICard(
                    icon: "figure.run",
                    iconColor: .blue,
                    title: "This Week",
                    value: String(format: "%.1f", thisWeekDistance),
                    unit: unitLabel,
                    subtitle: "\(thisWeekRuns) run\(thisWeekRuns == 1 ? "" : "s")"
                )
                KPICard(
                    icon: "speedometer",
                    iconColor: .orange,
                    title: "Avg Pace",
                    value: formatPace(avgPace),
                    unit: "/\(unitLabel)",
                    subtitle: "last 20 runs"
                )
            }
            HStack(spacing: 12) {
                KPICard(
                    icon: "road.lanes",
                    iconColor: .green,
                    title: "Total Distance",
                    value: String(format: "%.0f", totalDistance),
                    unit: unitLabel,
                    subtitle: "\(runs.count) runs"
                )
                KPICard(
                    icon: "trophy",
                    iconColor: .yellow,
                    title: "Longest Run",
                    value: String(format: "%.1f", longestRun),
                    unit: unitLabel,
                    subtitle: "personal best"
                )
            }
        }
    }

    // MARK: - Runs List

    private var runsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Runs")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                NavigationLink(destination: RunDetailView(run: run)) {
                    RunCard(run: run, useMiles: useMiles)
                }
                .buttonStyle(.plain)

                if index < runs.count - 1 {
                    Divider()
                        .padding(.leading, 64)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "figure.run")
                .font(.system(size: 50))
                .foregroundStyle(.quaternary)
            Text("No Runs Yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text("Connect Strava or tap + to log your first run.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private func deleteRuns(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(runs[index])
        }
    }
}

// MARK: - KPI Card

private struct KPICard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let unit: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Run Card

private struct RunCard: View {
    let run: Run
    let useMiles: Bool

    private var unitLabel: String { useMiles ? "mi" : "km" }

    private func dist(_ km: Double) -> Double {
        useMiles ? km * 0.621371 : km
    }

    private func paceForRun() -> Double {
        let d = dist(run.distance)
        guard d > 0 else { return 0 }
        return (Double(run.movingTime ?? run.duration) / 60.0) / d
    }

    private func formatPace(_ minPerUnit: Double) -> String {
        guard minPerUnit > 0, minPerUnit.isFinite else { return "--:--" }
        let mins = Int(minPerUnit)
        let secs = Int((minPerUnit - Double(mins)) * 60)
        return String(format: "%d:%02d", mins, secs)
    }

    private var workoutLabel: String {
        switch run.workoutType {
        case 1: return "Race"
        case 2: return "Long Run"
        case 3: return "Workout"
        default:
            let name = (run.name ?? "").lowercased()
            if name.contains("tempo") || name.contains("threshold") { return "Tempo" }
            if name.contains("interval") || name.contains("speed") { return "Intervals" }
            if name.contains("long") { return "Long Run" }
            if dist(run.distance) >= 13 { return "Long Run" }
            return "Easy"
        }
    }

    private var workoutColor: Color {
        switch workoutLabel {
        case "Race": return .red
        case "Long Run": return .purple
        case "Workout", "Tempo", "Intervals": return .orange
        default: return .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Workout type badge
            Circle()
                .fill(workoutColor.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: workoutLabel == "Race" ? "trophy.fill" :
                            workoutLabel == "Long Run" ? "road.lanes" :
                            workoutLabel == "Easy" ? "figure.run" : "bolt.fill")
                        .font(.subheadline)
                        .foregroundStyle(workoutColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(run.name ?? workoutLabel)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Text(run.date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 14) {
                    Label(String(format: "%.1f %@", dist(run.distance), unitLabel), systemImage: "map")
                    Label(formatPace(paceForRun()) + "/\(unitLabel)", systemImage: "speedometer")
                    if let hr = run.averageHeartrate {
                        Label("\(Int(hr))", systemImage: "heart.fill")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    RunListView()
        .modelContainer(for: [Run.self, UserProfile.self, CoachingResponse.self], inMemory: true)
}
