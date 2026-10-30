import Foundation

public enum RecommendationStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case reviewed = "REVIEWED"
    case archived = "ARCHIVED"
}

public struct AdvisorRecommendation: Identifiable, Codable, Sendable {
    public var id: String
    public var advisorId: String
    public var clientId: String
    public var title: String
    public var message: String
    public var status: RecommendationStatus
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        advisorId: String,
        clientId: String,
        title: String,
        message: String,
        status: RecommendationStatus = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.advisorId = advisorId
        self.clientId = clientId
        self.title = title
        self.message = message
        self.status = status
        self.createdAt = createdAt
    }
}