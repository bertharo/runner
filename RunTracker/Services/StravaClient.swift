import Foundation
import SwiftData

@MainActor
final class StravaClient: ObservableObject {
    @Published var isSyncing = false
    @Published var syncStatus: String?

    private static let stravaAPI = "https://www.strava.com/api/v3"
    private static let pageSize = 100

    private let auth: StravaAuth

    init(auth: StravaAuth) {
        self.auth = auth
    }

    func syncActivities(modelContext: ModelContext) async {
        isSyncing = true
        syncStatus = "Starting sync..."
        defer { isSyncing = false }

        do {
            let token = try await auth.getValidAccessToken()
            let latestDate = fetchLatestStravaDate(modelContext: modelContext)

            var after: Int?
            if let latestDate {
                after = Int(latestDate.timeIntervalSince1970) - 86400
            }

            var page = 1
            var totalSynced = 0
            var hasMore = true

            while hasMore {
                var components = URLComponents(string: "\(Self.stravaAPI)/athlete/activities")!
                components.queryItems = [
                    URLQueryItem(name: "per_page", value: String(Self.pageSize)),
                    URLQueryItem(name: "page", value: String(page)),
                ]
                if let after {
                    components.queryItems?.append(URLQueryItem(name: "after", value: String(after)))
                }

                var request = URLRequest(url: components.url!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as! HTTPURLResponse

                if http.statusCode == 429 {
                    syncStatus = "Rate limited. Try again in 15 minutes."
                    break
                }

                guard http.statusCode == 200 else {
                    let body = String(data: data, encoding: .utf8) ?? "unknown"
                    syncStatus = "Strava API error (\(http.statusCode)): \(body)"
                    break
                }

                let activities = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

                if activities.isEmpty {
                    hasMore = false
                    break
                }

                for act in activities {
                    guard let type = act["type"] as? String, type == "Run" else { continue }
                    upsertActivity(act, modelContext: modelContext)
                    totalSynced += 1
                }

                syncStatus = "Page \(page): \(totalSynced) runs synced..."

                if activities.count < Self.pageSize {
                    hasMore = false
                } else {
                    page += 1
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            }

            try modelContext.save()
            syncStatus = "Sync complete. \(totalSynced) runs processed."
        } catch {
            syncStatus = "Sync failed: \(error.localizedDescription)"
        }
    }

    private func fetchLatestStravaDate(modelContext: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { $0.syncedFromStrava == true },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first?.date
    }

    private func upsertActivity(_ act: [String: Any], modelContext: ModelContext) {
        guard let stravaId = act["id"] as? Int else { return }

        let distanceMeters = act["distance"] as? Double ?? 0
        let distanceKm = distanceMeters / 1000.0
        let movingTime = act["moving_time"] as? Int ?? 0

        let dateString = act["start_date"] as? String ?? ""
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: dateString) ?? Date()

        // Check for existing run with this stravaId
        let descriptor = FetchDescriptor<Run>(
            predicate: #Predicate<Run> { run in run.stravaId == stravaId }
        )
        let existing = try? modelContext.fetch(descriptor).first

        let run: Run
        if let existing {
            run = existing
        } else {
            run = Run(distance: distanceKm, duration: movingTime, date: date)
            modelContext.insert(run)
        }

        run.distance = distanceKm
        run.duration = movingTime
        run.date = date
        run.stravaId = stravaId
        run.name = act["name"] as? String
        run.elapsedTime = act["elapsed_time"] as? Int
        run.movingTime = movingTime
        run.totalElevationGain = act["total_elevation_gain"] as? Double
        run.averageSpeed = act["average_speed"] as? Double
        run.maxSpeed = act["max_speed"] as? Double
        run.averageHeartrate = act["average_heartrate"] as? Double
        run.maxHeartrate = act["max_heartrate"] as? Double
        run.sufferScore = act["suffer_score"] as? Int
        run.workoutType = act["workout_type"] as? Int
        run.stravaDescription = act["description"] as? String
        run.syncedFromStrava = true
    }
}
