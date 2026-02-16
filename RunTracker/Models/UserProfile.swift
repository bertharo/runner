import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var goalRace: String
    var goalDate: String?
    var goalTime: String?
    var weeklyMileageTarget: Double?

    init(goalRace: String, goalDate: String? = nil, goalTime: String? = nil, weeklyMileageTarget: Double? = nil) {
        self.id = UUID()
        self.goalRace = goalRace
        self.goalDate = goalDate
        self.goalTime = goalTime
        self.weeklyMileageTarget = weeklyMileageTarget
    }
}
