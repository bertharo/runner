import Foundation

struct PaceFormatter {
    static func formatted(pace: Double) -> String {
        guard pace > 0, pace.isFinite else { return "--:--" }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    static func formattedDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func formattedDistance(km: Double) -> String {
        return String(format: "%.2f km", km)
    }
}
