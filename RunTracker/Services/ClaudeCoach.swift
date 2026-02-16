import Foundation
import SwiftData

@MainActor
final class ClaudeCoach: ObservableObject {
    @Published var isLoading = false
    @Published var latestResponse: String?
    @Published var errorMessage: String?

    private static let apiURL = "https://api.anthropic.com/v1/messages"

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""
    }

    // MARK: - Public Commands

    func analyzeTraining(modelContext: ModelContext) async {
        await sendToCoach(
            command: "analyze",
            userMessage: """
            Analyze my current training. Focus on:
            1. Is my weekly mileage progression safe? Flag any week-over-week increases over 10%.
            2. Am I running my easy days easy enough?
            3. Are there back-to-back hard efforts I should be concerned about?
            4. Any heart rate trends that suggest accumulating fatigue?
            5. How does my training align with my goal (if set)?

            Be specific with numbers. Tell me what to change.
            """,
            modelContext: modelContext
        )
    }

    func weeklySummary(modelContext: ModelContext) async {
        await sendToCoach(
            command: "week",
            userMessage: """
            Give me a weekly summary covering:
            1. What I did this week — total mileage, number of runs, key workouts.
            2. What went well and what's concerning.
            3. Specific recommendations for next week — what days to run, suggested mileage, what type of runs.
            4. One thing I should focus on improving.

            Keep it actionable. I want a plan for the next 7 days.
            """,
            modelContext: modelContext
        )
    }

    func askCoach(question: String, modelContext: ModelContext) async {
        await sendToCoach(
            command: "ask",
            userMessage: """
            The athlete is asking: "\(question)"

            Answer based on their training data above. Be specific and reference their recent runs when relevant.
            """,
            modelContext: modelContext
        )
    }

    // MARK: - Core Send

    private func sendToCoach(command: String, userMessage: String, modelContext: ModelContext) async {
        guard !apiKey.isEmpty else {
            errorMessage = "Enter your Anthropic API key in Settings."
            return
        }

        isLoading = true
        errorMessage = nil
        latestResponse = nil
        defer { isLoading = false }

        do {
            let systemPrompt = buildSystemPrompt(modelContext: modelContext)
            let trainingContext = buildTrainingContext(modelContext: modelContext)
            let fullMessage = "## Training Data\n\n\(trainingContext)\n\n---\n\n\(userMessage)"

            let body: [String: Any] = [
                "model": "claude-sonnet-4-5-20250929",
                "max_tokens": 2048,
                "system": systemPrompt,
                "messages": [["role": "user", "content": fullMessage]],
            ]

            var request = URLRequest(url: URL(string: Self.apiURL)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as! HTTPURLResponse

            guard http.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
                errorMessage = "Claude API error (\(http.statusCode)): \(errorBody)"
                return
            }

            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let content = json["content"] as? [[String: Any]] ?? []
            let text = content
                .filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")

            latestResponse = text

            // Save to coaching history
            let entry = CoachingResponse(command: command, prompt: fullMessage, response: text)
            modelContext.insert(entry)
            try modelContext.save()
        } catch {
            errorMessage = "Request failed: \(error.localizedDescription)"
        }
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(modelContext: ModelContext) -> String {
        var persona = loadPersona()

        let descriptor = FetchDescriptor<UserProfile>()
        if let profile = try? modelContext.fetch(descriptor).first {
            persona += "\n\n## Athlete's Goal\n"
            persona += "Race: \(profile.goalRace)\n"
            if let d = profile.goalDate { persona += "Date: \(d)\n" }
            if let t = profile.goalTime { persona += "Target Time: \(t)\n" }
            if let m = profile.weeklyMileageTarget { persona += "Weekly Mileage Target: \(m) miles\n" }
        }

        return persona
    }

    private func loadPersona() -> String {
        guard let url = Bundle.main.url(forResource: "coaching-persona", withExtension: "md"),
              let content = try? String(contentsOf: url) else {
            return "You are an experienced running coach. Be direct and data-driven."
        }
        return content
    }

    // MARK: - Training Context Builder (ported from context.ts)

    private func buildTrainingContext(modelContext: ModelContext) -> String {
        let descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let activities = try? modelContext.fetch(descriptor), !activities.isEmpty else {
            return "No running activities found. Sync activities from Strava first."
        }

        let allRuns = activities.map { toActivitySummary($0) }
        let weeks = groupByWeek(activities)
        let sortedWeeks = weeks.sorted { $0.key > $1.key }.map(\.value)

        var lines: [String] = []

        // Goal context
        let profileDescriptor = FetchDescriptor<UserProfile>()
        if let profile = try? modelContext.fetch(profileDescriptor).first {
            lines.append("## Goal")
            lines.append("Race: \(profile.goalRace)")
            if let d = profile.goalDate { lines.append("Date: \(d)") }
            if let t = profile.goalTime { lines.append("Target Time: \(t)") }
            if let m = profile.weeklyMileageTarget { lines.append("Weekly Mileage Target: \(m) miles") }
            lines.append("")
        }

        // Current week detail
        if let currentWeek = sortedWeeks.first {
            lines.append("## Current Week")
            lines.append("Week of \(currentWeek.weekStart) | \(r2(currentWeek.totalMiles)) miles | \(currentWeek.runCount) runs")
            lines.append("")
            for run in currentWeek.runs {
                var line = "- \(run.date) | \(run.name) | \(r2(run.miles)) mi | \(formatPace(run.paceMinPerMile))/mi | \(run.durationFormatted) | \(run.workoutType)"
                if run.elevationGainFt > 0 { line += " | +\(run.elevationGainFt)ft" }
                if let hr = run.avgHr { line += " | HR avg:\(Int(hr)) max:\(run.maxHr.map { "\(Int($0))" } ?? "?")" }
                if let desc = run.runDescription { line += " | \"\(desc)\"" }
                lines.append(line)
            }
            lines.append("")
        }

        // Weekly mileage trend (last 4-5 weeks)
        let recentWeeks = Array(sortedWeeks.prefix(5))
        if recentWeeks.count >= 2 {
            lines.append("## Weekly Mileage Trend (last 4-5 weeks)")
            for i in 0..<recentWeeks.count {
                let w = recentWeeks[i]
                var line = "- \(w.weekStart): \(r2(w.totalMiles)) mi (\(w.runCount) runs)"
                if i < recentWeeks.count - 1 {
                    let prev = recentWeeks[i + 1]
                    if prev.totalMiles > 0 {
                        let change = ((w.totalMiles - prev.totalMiles) / prev.totalMiles) * 100
                        let sign = change >= 0 ? "+" : ""
                        line += " [\(sign)\(String(format: "%.1f", change))% vs prior week]"
                    }
                }
                lines.append(line)
            }
            lines.append("")
        }

        // Long run history
        let longRuns = allRuns
            .filter { $0.workoutType == "Long Run" || $0.miles >= 10 }
            .prefix(6)
        if !longRuns.isEmpty {
            lines.append("## Long Run History (last 6)")
            for run in longRuns {
                var line = "- \(run.date): \(r2(run.miles)) mi @ \(formatPace(run.paceMinPerMile))/mi"
                if let hr = run.avgHr { line += " | HR \(Int(hr))" }
                if run.elevationGainFt > 0 { line += " | +\(run.elevationGainFt)ft" }
                lines.append(line)
            }
            lines.append("")
        }

        // Pace summary
        let easyRuns = Array(allRuns.filter { $0.workoutType == "Easy" || $0.workoutType == "Long Run" }.prefix(20))
        let workoutRuns = Array(allRuns.filter { ["Workout", "Tempo", "Intervals", "Race"].contains($0.workoutType) }.prefix(10))
        if !easyRuns.isEmpty || !workoutRuns.isEmpty {
            lines.append("## Pace Summary")
            if !easyRuns.isEmpty {
                let avg = easyRuns.reduce(0.0) { $0 + $1.paceMinPerMile } / Double(easyRuns.count)
                lines.append("Easy/Long Run avg pace (last \(easyRuns.count)): \(formatPace(avg))/mi")
            }
            if !workoutRuns.isEmpty {
                let avg = workoutRuns.reduce(0.0) { $0 + $1.paceMinPerMile } / Double(workoutRuns.count)
                lines.append("Workout avg pace (last \(workoutRuns.count)): \(formatPace(avg))/mi")
            }
            lines.append("")
        }

        // Heart rate trends
        let runsWithHr = Array(allRuns.filter { $0.avgHr != nil }.prefix(20))
        if runsWithHr.count >= 4 {
            lines.append("## Heart Rate Trends")
            let recentHr = Array(runsWithHr.prefix(5))
            let olderHr = Array(runsWithHr.dropFirst(5).prefix(5))

            let recentAvg = recentHr.reduce(0.0) { $0 + ($1.avgHr ?? 0) } / Double(recentHr.count)
            lines.append("Recent 5-run avg HR: \(Int(recentAvg))")

            if !olderHr.isEmpty {
                let olderAvg = olderHr.reduce(0.0) { $0 + ($1.avgHr ?? 0) } / Double(olderHr.count)
                lines.append("Prior 5-run avg HR: \(Int(olderAvg))")
                let drift = recentAvg - olderAvg
                if abs(drift) >= 3 {
                    let sign = drift > 0 ? "+" : ""
                    let meaning = drift > 0 ? "upward — possible fatigue" : "downward — improving fitness"
                    lines.append("HR drift: \(sign)\(String(format: "%.1f", drift)) bpm (\(meaning))")
                }
            }
            lines.append("")
        }

        // Last 14 days
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let recentRuns = allRuns.filter {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withFullDate]
            if let d = dateFormatter.date(from: $0.date) { return d >= twoWeeksAgo }
            // Fallback: try simple date parsing
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            if let d = df.date(from: $0.date) { return d >= twoWeeksAgo }
            return false
        }
        if !recentRuns.isEmpty {
            lines.append("## Last 14 Days (for pattern detection)")
            for run in recentRuns {
                var line = "- \(run.date) | \(run.workoutType) | \(r2(run.miles)) mi @ \(formatPace(run.paceMinPerMile))/mi"
                if let hr = run.avgHr { line += " | HR \(Int(hr))" }
                lines.append(line)
            }
            lines.append("")
        }

        // Overall stats
        let totalMiles = allRuns.reduce(0.0) { $0 + $1.miles }
        let first = allRuns.last?.date ?? "?"
        let last = allRuns.first?.date ?? "?"
        lines.append("## Overall Stats")
        lines.append("Total activities: \(allRuns.count) runs")
        lines.append("Total mileage: \(String(format: "%.1f", totalMiles)) miles")
        lines.append("Date range: \(first) to \(last)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Context Helpers

    private struct ActivitySummary {
        let date: String
        let name: String
        let miles: Double
        let paceMinPerMile: Double
        let durationFormatted: String
        let elevationGainFt: Int
        let avgHr: Double?
        let maxHr: Double?
        let workoutType: String
        let runDescription: String?
    }

    private func toActivitySummary(_ run: Run) -> ActivitySummary {
        let miles = run.distance * 0.621371 // km to miles
        let movingTime = run.movingTime ?? run.duration
        let paceMinPerMile: Double = {
            guard let speed = run.averageSpeed, speed > 0 else {
                // Compute from distance/time
                guard miles > 0 else { return 0 }
                return (Double(movingTime) / 60.0) / miles
            }
            return 26.8224 / speed
        }()

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        return ActivitySummary(
            date: df.string(from: run.date),
            name: run.name ?? "Run",
            miles: (miles * 100).rounded() / 100,
            paceMinPerMile: paceMinPerMile,
            durationFormatted: formatDuration(movingTime),
            elevationGainFt: run.totalElevationGain.map { Int(($0 * 3.28084).rounded()) } ?? 0,
            avgHr: run.averageHeartrate,
            maxHr: run.maxHeartrate,
            workoutType: classifyWorkout(run),
            runDescription: run.stravaDescription
        )
    }

    private func classifyWorkout(_ run: Run) -> String {
        switch run.workoutType {
        case 1: return "Race"
        case 2: return "Long Run"
        case 3: return "Workout"
        default:
            let miles = run.distance * 0.621371
            let name = (run.name ?? "").lowercased()
            if name.contains("tempo") || name.contains("threshold") { return "Tempo" }
            if name.contains("interval") || name.contains("repeat") || name.contains("speed") { return "Intervals" }
            if name.contains("long") { return "Long Run" }
            if name.contains("easy") || name.contains("recovery") { return "Easy" }
            if miles >= 13 { return "Long Run" }
            return "Easy"
        }
    }

    private struct WeekSummary {
        let weekStart: String
        var totalMiles: Double
        var runCount: Int
        var runs: [ActivitySummary]
    }

    private func groupByWeek(_ activities: [Run]) -> [String: WeekSummary] {
        var weeks: [String: WeekSummary] = [:]

        for act in activities {
            let weekStart = getWeekStart(act.date)
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let label = df.string(from: weekStart)
            let summary = toActivitySummary(act)

            if weeks[label] == nil {
                weeks[label] = WeekSummary(weekStart: label, totalMiles: 0, runCount: 0, runs: [])
            }
            weeks[label]!.totalMiles += summary.miles
            weeks[label]!.runCount += 1
            weeks[label]!.runs.append(summary)
        }

        // Round totals
        for key in weeks.keys {
            weeks[key]!.totalMiles = (weeks[key]!.totalMiles * 100).rounded() / 100
        }

        return weeks
    }

    private func getWeekStart(_ date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    private func formatPace(_ minPerMile: Double) -> String {
        guard minPerMile > 0, minPerMile.isFinite else { return "--:--" }
        let mins = Int(minPerMile)
        let secs = Int((minPerMile - Double(mins)) * 60)
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        return "\(m)m \(s)s"
    }

    private func r2(_ val: Double) -> String {
        String(format: "%.2f", val)
    }
}
