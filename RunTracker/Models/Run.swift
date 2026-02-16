import Foundation
import SwiftData

@Model
final class Run {
    var id: UUID
    var distance: Double
    var duration: Int
    var date: Date
    var notes: String

    // Strava fields
    var stravaId: Int?
    var name: String?
    var elapsedTime: Int?
    var movingTime: Int?
    var totalElevationGain: Double?
    var averageSpeed: Double?
    var maxSpeed: Double?
    var averageHeartrate: Double?
    var maxHeartrate: Double?
    var sufferScore: Int?
    var workoutType: Int?
    var stravaDescription: String?
    var syncedFromStrava: Bool

    var pace: Double {
        guard distance > 0 else { return 0 }
        return (Double(duration) / 60.0) / distance
    }

    init(distance: Double, duration: Int, date: Date, notes: String = "") {
        self.id = UUID()
        self.distance = distance
        self.duration = duration
        self.date = date
        self.notes = notes
        self.syncedFromStrava = false
    }
}
