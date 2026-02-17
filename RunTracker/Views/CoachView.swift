import SwiftUI
import SwiftData
import Charts

struct CoachView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Run.date, order: .reverse) private var runs: [Run]
    @Query(sort: \CoachingResponse.createdAt, order: .reverse) private var history: [CoachingResponse]
    @Query private var profiles: [UserProfile]
    @AppStorage("use_miles") private var useMiles = true

    @State private var showingCoachSheet = false

    // MARK: - Helpers

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        return cal
    }

    private var unitLabel: String { useMiles ? "mi" : "km" }

    private func distanceInUnit(_ km: Double) -> Double {
        useMiles ? km * 0.621371 : km
    }

    private func paceInUnit(_ run: Run) -> Double {
        let dist = distanceInUnit(run.distance)
        guard dist > 0 else { return 0 }
        return (Double(run.movingTime ?? run.duration) / 60.0) / dist
    }

    private func formatPace(_ minPerUnit: Double) -> String {
        guard minPerUnit > 0, minPerUnit.isFinite else { return "--:--" }
        let mins = Int(minPerUnit)
        let secs = Int((minPerUnit - Double(mins)) * 60)
        return String(format: "%d:%02d", mins, secs)
    }

    private func classifyWorkout(_ run: Run) -> String {
        switch run.workoutType {
        case 1: return "Race"
        case 2: return "Long Run"
        case 3: return "Workout"
        default:
            let name = (run.name ?? "").lowercased()
            if name.contains("tempo") || name.contains("threshold") { return "Tempo" }
            if name.contains("interval") || name.contains("repeat") || name.contains("speed") { return "Intervals" }
            if name.contains("long") { return "Long Run" }
            if name.contains("easy") || name.contains("recovery") { return "Easy" }
            if run.distance * 0.621371 >= 13 { return "Long Run" }
            return "Easy"
        }
    }

    // MARK: - This Week Data

    private var thisWeekRuns: [Run] {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        guard let start = calendar.date(from: comps) else { return [] }
        return runs.filter { $0.date >= start }
    }

    private var thisWeekDistance: Double {
        thisWeekRuns.reduce(0) { $0 + distanceInUnit($1.distance) }
    }

    private var thisWeekAvgPace: Double {
        let valid = thisWeekRuns.filter { $0.distance > 0 }
        guard !valid.isEmpty else { return 0 }
        let total = valid.reduce(0.0) { $0 + paceInUnit($1) }
        return total / Double(valid.count)
    }

    // MARK: - Weekly Mileage Data (last 8 weeks)

    private struct WeekData: Identifiable {
        let id = UUID()
        let weekStart: Date
        let label: String
        let distance: Double
        let isCurrent: Bool
    }

    private var weeklyMileageData: [WeekData] {
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "M/d"

        let currentComps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let currentWeekStart = calendar.date(from: currentComps)

        return (0..<8).reversed().compactMap { i -> WeekData? in
            guard let weekDate = calendar.date(byAdding: .weekOfYear, value: -i, to: now) else { return nil }
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekDate)
            guard let weekStart = calendar.date(from: comps),
                  let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { return nil }

            let total = runs
                .filter { $0.date >= weekStart && $0.date < weekEnd }
                .reduce(0.0) { $0 + distanceInUnit($1.distance) }

            return WeekData(
                weekStart: weekStart,
                label: df.string(from: weekStart),
                distance: (total * 10).rounded() / 10,
                isCurrent: weekStart == currentWeekStart
            )
        }
    }

    // MARK: - Pace Trend Data (last 15 runs)

    private struct PacePoint: Identifiable {
        let id = UUID()
        let date: Date
        let pace: Double
        let category: String
    }

    private var paceTrendData: [PacePoint] {
        runs.prefix(15)
            .filter { $0.distance > 0 }
            .reversed()
            .map { run in
                let pace = paceInUnit(run)
                let type = classifyWorkout(run)
                let category = ["Workout", "Tempo", "Intervals", "Race"].contains(type) ? "Workout" : "Easy"
                return PacePoint(date: run.date, pace: pace, category: category)
            }
    }

    // MARK: - Heart Rate Data (last 15 with HR)

    private struct HRPoint: Identifiable {
        let id = UUID()
        let date: Date
        let hr: Double
    }

    private var hrTrendData: [HRPoint] {
        runs.filter { $0.averageHeartrate != nil }
            .prefix(15)
            .reversed()
            .map { HRPoint(date: $0.date, hr: $0.averageHeartrate!) }
    }

    private var avgHR: Double {
        guard !hrTrendData.isEmpty else { return 0 }
        return hrTrendData.reduce(0) { $0 + $1.hr } / Double(hrTrendData.count)
    }

    // MARK: - Goal Pace

    private var goalPace: Double? {
        guard let profile = profiles.first,
              let timeStr = profile.goalTime, !timeStr.isEmpty else { return nil }

        let parts = timeStr.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        let totalMinutes: Double
        if parts.count == 3 {
            totalMinutes = parts[0] * 60 + parts[1] + parts[2] / 60
        } else {
            totalMinutes = parts[0] + parts[1] / 60
        }

        let race = profile.goalRace.lowercased()
        let distanceMiles: Double
        if race.contains("marathon") && !race.contains("half") {
            distanceMiles = 26.2
        } else if race.contains("half") {
            distanceMiles = 13.1
        } else if race.contains("10k") {
            distanceMiles = 6.2
        } else if race.contains("5k") {
            distanceMiles = 3.1
        } else {
            return nil
        }

        let pacePerMile = totalMinutes / distanceMiles
        return useMiles ? pacePerMile : pacePerMile / 1.60934
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    thisWeekSection

                    if weeklyMileageData.contains(where: { $0.distance > 0 }) {
                        weeklyMileageChart
                    }

                    if paceTrendData.count >= 3 {
                        paceTrendChart
                    }

                    if hrTrendData.count >= 4 {
                        hrTrendChart
                    }

                    aiCoachCard
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Coach")
            .sheet(isPresented: $showingCoachSheet) {
                CoachSheet()
            }
        }
    }

    // MARK: - This Week Summary

    private var thisWeekSection: some View {
        HStack(spacing: 12) {
            DashboardStat(
                title: unitLabel.uppercased(),
                value: String(format: "%.1f", thisWeekDistance),
                icon: "figure.run"
            )
            DashboardStat(
                title: "AVG PACE",
                value: thisWeekAvgPace > 0 ? formatPace(thisWeekAvgPace) : "--:--",
                icon: "speedometer"
            )
            DashboardStat(
                title: "RUNS",
                value: "\(thisWeekRuns.count)",
                icon: "calendar"
            )
        }
    }

    // MARK: - Weekly Mileage Chart

    private var weeklyMileageChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Mileage")
                .font(.subheadline)
                .fontWeight(.semibold)

            Chart(weeklyMileageData) { week in
                BarMark(
                    x: .value("Week", week.label),
                    y: .value(unitLabel, week.distance)
                )
                .foregroundStyle(week.isCurrent ? Color.accentColor : Color.accentColor.opacity(0.45))
                .cornerRadius(4)
                .annotation(position: .top, spacing: 4) {
                    if week.isCurrent && week.distance > 0 {
                        Text(String(format: "%.1f", week.distance))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYAxisLabel(unitLabel)
            .frame(height: 180)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Pace Trend Chart

    private var paceTrendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pace Trend")
                .font(.subheadline)
                .fontWeight(.semibold)

            Chart {
                ForEach(paceTrendData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Pace", -point.pace)
                    )
                    .foregroundStyle(Color.secondary.opacity(0.3))
                    .interpolationMethod(.catmullRom)
                }

                ForEach(paceTrendData) { point in
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Pace", -point.pace)
                    )
                    .foregroundStyle(by: .value("Type", point.category))
                    .symbolSize(30)
                }

                if let goal = goalPace {
                    RuleMark(y: .value("Goal", -goal))
                        .foregroundStyle(.green.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .annotation(position: .leading, spacing: 4) {
                            Text("Goal")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                }
            }
            .chartForegroundStyleScale(domain: ["Easy", "Workout"], range: [Color.blue, Color.orange])
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(formatPace(-v))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartLegend(position: .top, alignment: .trailing)
            .frame(height: 180)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Heart Rate Chart

    private var hrTrendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heart Rate Trend")
                .font(.subheadline)
                .fontWeight(.semibold)

            Chart {
                ForEach(hrTrendData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("BPM", point.hr)
                    )
                    .foregroundStyle(Color.red.opacity(0.7))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("BPM", point.hr)
                    )
                    .foregroundStyle(Color.red)
                    .symbolSize(24)
                }

                RuleMark(y: .value("Avg", avgHR))
                    .foregroundStyle(.red.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .trailing, spacing: 4) {
                        Text("\(Int(avgHR)) avg")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - AI Coach Card

    private var aiCoachCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Coach")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Training analysis & personalized feedback")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button {
                showingCoachSheet = true
            } label: {
                Text("Get AI Feedback")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Dashboard Stat Card

private struct DashboardStat: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Coach Sheet (existing coaching UI)

private struct CoachSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CoachingResponse.createdAt, order: .reverse) private var history: [CoachingResponse]
    @StateObject private var coach = ClaudeCoach()

    @State private var selectedTab = 0
    @State private var question = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Command", selection: $selectedTab) {
                    Text("Analyze").tag(0)
                    Text("Weekly").tag(1)
                    Text("Ask").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if selectedTab == 2 {
                    HStack(spacing: 10) {
                        TextField("Ask your coach...", text: $question)
                            .padding(10)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button {
                            let q = question
                            question = ""
                            Task { await coach.askCoach(question: q, modelContext: modelContext) }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || coach.isLoading)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                } else {
                    Button {
                        Task {
                            if selectedTab == 0 {
                                await coach.analyzeTraining(modelContext: modelContext)
                            } else {
                                await coach.weeklySummary(modelContext: modelContext)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectedTab == 0 ? "chart.bar" : "calendar")
                            Text(selectedTab == 0 ? "Analyze Training" : "Weekly Summary")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coach.isLoading)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }

                Divider()

                if coach.isLoading {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Analyzing...")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                } else if let error = coach.errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                } else if let response = coach.latestResponse {
                    coachingContent(response)
                } else if history.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 44))
                            .foregroundStyle(.quaternary)
                        Text("Your AI Coach")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Analyze training, get weekly plans,\nor ask a question.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    historyList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Coaching Response Cards

    private func coachingContent(_ text: String) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                let sections = parseSections(text)
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    CoachCard(section: section)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    private func parseSections(_ text: String) -> [CoachSection] {
        let parts = text.components(separatedBy: "\n---\n")
        var sections: [CoachSection] = []

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let lines = trimmed.components(separatedBy: "\n")
            var title: String?
            var bodyLines: [String] = []

            for line in lines {
                if line.hasPrefix("## ") && title == nil {
                    title = String(line.dropFirst(3))
                } else if line.hasPrefix("# ") && title == nil {
                    title = String(line.dropFirst(2))
                } else if line != "---" {
                    bodyLines.append(line)
                }
            }

            let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty || title != nil {
                sections.append(CoachSection(title: title, body: body))
            }
        }

        if sections.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(CoachSection(title: nil, body: text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return sections
    }

    // MARK: - History

    private var historyList: some View {
        List {
            ForEach(history.prefix(10)) { entry in
                NavigationLink {
                    coachingContent(entry.response)
                        .navigationTitle(entry.command.capitalized)
                        .background(Color(.systemGroupedBackground))
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.command.capitalized)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(entry.createdAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(entry.response.prefix(120).replacingOccurrences(of: "\n", with: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Data Types

private struct CoachSection {
    let title: String?
    let body: String
}

// MARK: - Card View

private struct CoachCard: View {
    let section: CoachSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = section.title {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }

            MarkdownBody(text: section.body)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Markdown Body Renderer

private struct MarkdownBody: View {
    let text: String

    var body: some View {
        let blocks = parseBlocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let content):
            markdownText(content)
        case .numberedItem(let num, let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(num).")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                    .frame(width: 20, alignment: .trailing)
                markdownText(content)
            }
        case .bulletItem(let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 5, height: 5)
                    .padding(.top, 5)
                markdownText(content)
            }
        case .heading(let content):
            Text(content)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.top, 4)
        }
    }

    private func markdownText(_ content: String) -> some View {
        Group {
            if let attributed = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributed)
            } else {
                Text(content)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineSpacing(3)
    }

    private enum Block {
        case paragraph(String)
        case numberedItem(Int, String)
        case bulletItem(String)
        case heading(String)
    }

    private func parseBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var currentParagraph: [String] = []

        func flushParagraph() {
            if !currentParagraph.isEmpty {
                blocks.append(.paragraph(currentParagraph.joined(separator: " ")))
                currentParagraph = []
            }
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            let numberPattern = /^(\*\*)?(\d+)\.\s*(.+?)(\*\*)?$/
            if let match = trimmed.wholeMatch(of: numberPattern) {
                flushParagraph()
                let num = Int(match.2) ?? 0
                let content = String(match.3)
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "**", with: "")
                blocks.append(.numberedItem(num, "**\(content)**"))
                continue
            }

            if trimmed.hasPrefix("- ") {
                flushParagraph()
                blocks.append(.bulletItem(String(trimmed.dropFirst(2))))
                continue
            }

            if trimmed.hasPrefix("### ") {
                flushParagraph()
                blocks.append(.heading(String(trimmed.dropFirst(4))))
                continue
            }
            if trimmed.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(String(trimmed.dropFirst(3))))
                continue
            }

            currentParagraph.append(trimmed)
        }

        flushParagraph()
        return blocks
    }
}

#Preview {
    CoachView()
        .modelContainer(for: [Run.self, UserProfile.self, CoachingResponse.self], inMemory: true)
}
