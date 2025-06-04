import Foundation

/// Example model for testing and documentation
@ORMTable
public struct User: ORMTable {
    public typealias IDType = Int
    
    public var id: Int = 0
    public var username: String
    public var email: String
    public var firstName: String
    public var lastName: String
    public var createdAt: Date
    public var updatedAt: Date?
    public var deletedAt: Date?
    public var isActive: Bool = true
    public var score: Double = 0.0
    public var metadata: Data?
    
    public static var tableName: String { "users" }
    
    public static var columnMappings: [String: String]? {
        [
            "username": "user_name",
            "email": "email_address"
        ]
    }
    
    public static var indexes: [ORMIndex] {
        [
            ORMIndex(name: "idx_users_email", columns: ["email_address"]),
            ORMIndex(name: "idx_users_createdat", columns: ["createdAt"])
        ]
    }
    
    public static var uniqueConstraints: [ORMUniqueConstraint] {
        [
            ORMUniqueConstraint(name: "uniq_users_username", columns: ["user_name"])
        ]
    }
    
    public init(username: String, email: String, firstName: String, lastName: String, createdAt: Date, updatedAt: Date? = nil, deletedAt: Date? = nil, isActive: Bool = true, score: Double = 0.0, metadata: Data? = nil) {
        self.username = username
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isActive = isActive
        self.score = score
        self.metadata = metadata
    }
}