import SwiftUI
import SwiftData

struct RunDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("use_miles") private var useMiles = true
    let run: Run
    @State private var showingDeleteConfirmation = false

    private var unitLabel: String { useMiles ? "mi" : "km" }

    private func dist(_ km: Double) -> Double {
        useMiles ? km * 0.621371 : km
    }

    private func pace() -> Double {
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

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 6) {
                    if let name = run.name {
                        Text(name)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Text(run.date.formatted(date: .long, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Primary KPIs
                HStack(spacing: 12) {
                    DetailKPI(
                        icon: "map",
                        iconColor: .blue,
                        value: String(format: "%.2f", dist(run.distance)),
                        unit: unitLabel
                    )
                    DetailKPI(
                        icon: "speedometer",
                        iconColor: .orange,
                        value: formatPace(pace()),
                        unit: "/\(unitLabel)"
                    )
                    DetailKPI(
                        icon: "clock",
                        iconColor: .green,
                        value: formatDuration(run.movingTime ?? run.duration),
                        unit: ""
                    )
                }

                // Heart Rate
                if run.averageHeartrate != nil || run.maxHeartrate != nil {
                    HStack(spacing: 12) {
                        if let avg = run.averageHeartrate {
                            DetailKPI(
                                icon: "heart.fill",
                                iconColor: .red,
                                value: "\(Int(avg))",
                                unit: "avg bpm"
                            )
                        }
                        if let max = run.maxHeartrate {
                            DetailKPI(
                                icon: "heart",
                                iconColor: .red.opacity(0.7),
                                value: "\(Int(max))",
                                unit: "max bpm"
                            )
                        }
                        if run.averageHeartrate != nil && run.maxHeartrate == nil ||
                           run.averageHeartrate == nil && run.maxHeartrate != nil {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }

                // Secondary stats
                if run.totalElevationGain != nil || run.sufferScore != nil {
                    HStack(spacing: 12) {
                        if let elev = run.totalElevationGain {
                            DetailKPI(
                                icon: "mountain.2",
                                iconColor: .brown,
                                value: PaceFormatter.formattedElevation(meters: elev).replacingOccurrences(of: " ft", with: "").replacingOccurrences(of: " m", with: ""),
                                unit: useMiles ? "ft" : "m"
                            )
                        }
                        if let suffer = run.sufferScore {
                            DetailKPI(
                                icon: "flame",
                                iconColor: .orange,
                                value: "\(suffer)",
                                unit: "suffer"
                            )
                        }
                        if run.totalElevationGain != nil && run.sufferScore == nil ||
                           run.totalElevationGain == nil && run.sufferScore != nil {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }

                // Notes / Description
                if let desc = run.stravaDescription, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !run.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(run.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Delete
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text("Delete Run")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
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

// MARK: - Detail KPI Card

private struct DetailKPI: View {
    let icon: String
    let iconColor: Color
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(iconColor)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        RunDetailView(run: Run(distance: 5.0, duration: 1500, date: .now, notes: "Great run!"))
    }
    .modelContainer(for: Run.self, inMemory: true)
}
