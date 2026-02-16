import Foundation
import SwiftData

@Model
final class CoachingResponse {
    var id: UUID
    var command: String
    var prompt: String
    var response: String
    var createdAt: Date

    init(command: String, prompt: String, response: String) {
        self.id = UUID()
        self.command = command
        self.prompt = prompt
        self.response = response
        self.createdAt = Date()
    }
}
