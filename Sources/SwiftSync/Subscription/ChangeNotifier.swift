import Foundation
@preconcurrency import Combine

/// Manages change notifications for database tables
/// Provides a centralized system for tracking data mutations and notifying subscribers
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public actor ChangeNotifier {
    private var subjects: [String: PassthroughSubject<Void, Never>] = [:]
    
    public init() {}
    
    /// Get or create a publisher for the specified table
    /// - Parameter tableName: The name of the table to monitor
    /// - Returns: A publisher that emits when the table changes
    public func publisher(for tableName: String) -> AnyPublisher<Void, Never> {
        if let subject = subjects[tableName] {
            return subject.eraseToAnyPublisher()
        }
        
        let subject = PassthroughSubject<Void, Never>()
        subjects[tableName] = subject
        return subject.eraseToAnyPublisher()
    }
    
    /// Notify subscribers that a table has changed
    /// - Parameter tableName: The name of the table that changed
    public func notifyChange(for tableName: String) {
        if let subject = subjects[tableName] {
            DispatchQueue.main.async {
                subject.send(())
            }
        }
    }
    
    /// Remove all subscribers for a table
    /// - Parameter tableName: The name of the table to cleanup
    public func cleanup(for tableName: String) {
        if let subject = subjects[tableName] {
            DispatchQueue.main.async {
                subject.send(completion: .finished)
            }
        }
        subjects.removeValue(forKey: tableName)
    }
    
    /// Remove all subscribers and cleanup resources
    public func cleanupAll() {
        for subject in subjects.values {
            DispatchQueue.main.async {
                subject.send(completion: .finished)
            }
        }
        subjects.removeAll()
    }
}

/// A convenience type for table change notifications
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public struct TableChangeNotification: Sendable {
    public let tableName: String
    public let changeType: ChangeType
    public let timestamp: Date
    
    public enum ChangeType: String, Sendable {
        case insert = "INSERT"
        case update = "UPDATE"
        case delete = "DELETE"
    }
    
    public init(tableName: String, changeType: ChangeType) {
        self.tableName = tableName
        self.changeType = changeType
        self.timestamp = Date()
    }
}

/// Protocol for objects that can notify about their changes
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public protocol ChangeNotifying {
    var changeNotifier: ChangeNotifier { get }
}