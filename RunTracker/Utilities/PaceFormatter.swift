import Foundation
import SwiftUI

struct PaceFormatter {
    static var useMiles: Bool {
        UserDefaults.standard.object(forKey: "use_miles") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "use_miles")
    }

    static var unitLabel: String { useMiles ? "mi" : "km" }

    static func formatted(pace: Double) -> String {
        guard pace > 0, pace.isFinite else { return "--:--" }
        let adjusted = useMiles ? pace * 1.60934 : pace
        let minutes = Int(adjusted)
        let seconds = Int((adjusted - Double(minutes)) * 60)
        return String(format: "%d:%02d /\(unitLabel)", minutes, seconds)
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
        if useMiles {
            return String(format: "%.2f mi", km * 0.621371)
        }
        return String(format: "%.2f km", km)
    }

    static func formattedElevation(meters: Double) -> String {
        if useMiles {
            return String(format: "%.0f ft", meters * 3.28084)
        }
        return String(format: "%.0f m", meters)
    }
}
