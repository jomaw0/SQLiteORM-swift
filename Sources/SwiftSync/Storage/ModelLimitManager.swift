import Foundation

/// Removal strategy for when model limit is exceeded
public enum ModelRemovalStrategy: String, Codable, CaseIterable, Sendable {
    /// First In, First Out - Remove the oldest models by creation time
    case fifo = "fifo"
    /// Last In, First Out - Remove the newest models by creation time  
    case lifo = "lifo"
    /// Least Recently Used - Remove models that haven't been accessed recently
    case lru = "lru"
    /// Most Recently Used - Remove models that were accessed most recently
    case mru = "mru"
    /// Random - Remove random models
    case random = "random"
    /// Smallest First - Remove models with smallest ID values first
    case smallestFirst = "smallest_first"
    /// Largest First - Remove models with largest ID values first
    case largestFirst = "largest_first"
}

/// Configuration for model limits
public struct ModelLimit: Codable, Sendable {
    /// Maximum number of models to keep
    public let maxCount: Int
    
    /// Strategy to use when removing excess models
    public let removalStrategy: ModelRemovalStrategy
    
    /// Whether to enable model limit enforcement
    public let enabled: Bool
    
    /// Batch size for removal operations (default: 10% of max count, minimum 1)
    public let batchSize: Int
    
    public init(
        maxCount: Int,
        removalStrategy: ModelRemovalStrategy = .fifo,
        enabled: Bool = false,
        batchSize: Int? = nil
    ) {
        self.maxCount = maxCount
        self.removalStrategy = removalStrategy
        self.enabled = enabled
        self.batchSize = batchSize ?? max(1, maxCount / 10)
    }
    
    /// Disabled model limit configuration
    public static let disabled = ModelLimit(maxCount: 0, enabled: false)
}

/// Reasons why models were removed due to limits
public enum ModelRemovalReason: String, Codable, CaseIterable, Sendable {
    case limitExceeded = "limit_exceeded"
    case manualEnforcement = "manual_enforcement"
    case strategyChange = "strategy_change"
    case cleanup = "cleanup"
}

/// Information about models that were removed
public struct ModelRemovalInfo: Sendable {
    public let tableName: String
    public let removedCount: Int
    public let removalStrategy: ModelRemovalStrategy
    public let reason: ModelRemovalReason
    public let removedAt: Date
    
    public init(
        tableName: String,
        removedCount: Int,
        removalStrategy: ModelRemovalStrategy,
        reason: ModelRemovalReason,
        removedAt: Date = Date()
    ) {
        self.tableName = tableName
        self.removedCount = removedCount
        self.removalStrategy = removalStrategy
        self.reason = reason
        self.removedAt = removedAt
    }
}

/// Callback for model removal events
public typealias ModelRemovalCallback = @Sendable (ModelRemovalInfo) async -> Void

/// Errors that can occur during model limit management
public enum ModelLimitError: Error, LocalizedError {
    case invalidConfiguration(String)
    case removalFailed(String)
    case accessTrackingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid model limit configuration: \(message)"
        case .removalFailed(let message):
            return "Failed to remove excess models: \(message)"
        case .accessTrackingFailed(let message):
            return "Failed to track model access: \(message)"
        }
    }
}

/// Manages model limits and removal strategies for ORMTable types
public actor ModelLimitManager {
    /// Database connection
    private let database: SQLiteDatabase
    
    /// Disk storage manager for cleanup
    private let diskStorageManager: DiskStorageManager?
    
    /// Change notifier for reactive subscriptions
    private let changeNotifier: ChangeNotifier?
    
    /// Access tracking for LRU/MRU strategies
    private var accessTracker: [String: [String: Date]] = [:]
    
    /// Model limit configurations by table name
    private var modelLimits: [String: ModelLimit] = [:]
    
    /// Global removal callback for all model types
    private var globalRemovalCallback: ModelRemovalCallback?
    
    /// Per-table removal callbacks
    private var tableRemovalCallbacks: [String: ModelRemovalCallback] = [:]
    
    public init(database: SQLiteDatabase, diskStorageManager: DiskStorageManager? = nil, changeNotifier: ChangeNotifier? = nil) {
        self.database = database
        self.diskStorageManager = diskStorageManager
        self.changeNotifier = changeNotifier
    }
    
    /// Configure model limit for a specific table type
    /// - Parameters:
    ///   - modelType: The model type to configure
    ///   - limit: The model limit configuration
    public func setModelLimit<T: ORMTable>(for modelType: T.Type, limit: ModelLimit) {
        let tableName = T.tableName
        self.modelLimits[tableName] = limit
        
        // Initialize access tracker for LRU/MRU strategies
        if limit.removalStrategy == .lru || limit.removalStrategy == .mru {
            if self.accessTracker[tableName] == nil {
                self.accessTracker[tableName] = [:]
            }
        }
    }
    
    /// Get model limit configuration for a table type
    /// - Parameter modelType: The model type
    /// - Returns: Model limit configuration or nil if not set
    public func getModelLimit<T: ORMTable>(for modelType: T.Type) -> ModelLimit? {
        return self.modelLimits[T.tableName]
    }
    
    /// Remove model limit configuration for a table type
    /// - Parameter modelType: The model type
    public func removeModelLimit<T: ORMTable>(for modelType: T.Type) {
        let tableName = T.tableName
        self.modelLimits.removeValue(forKey: tableName)
        self.accessTracker.removeValue(forKey: tableName)
        self.tableRemovalCallbacks.removeValue(forKey: tableName)
    }
    
    /// Set global removal callback for all model types
    /// - Parameter callback: Callback to execute when models are removed
    public func setGlobalRemovalCallback(_ callback: ModelRemovalCallback?) {
        self.globalRemovalCallback = callback
    }
    
    /// Set removal callback for a specific table type
    /// - Parameters:
    ///   - modelType: The model type
    ///   - callback: Callback to execute when models of this type are removed
    public func setRemovalCallback<T: ORMTable>(for modelType: T.Type, callback: ModelRemovalCallback?) {
        let tableName = T.tableName
        if let callback = callback {
            self.tableRemovalCallbacks[tableName] = callback
        } else {
            self.tableRemovalCallbacks.removeValue(forKey: tableName)
        }
    }
    
    /// Track model access for LRU/MRU strategies
    /// - Parameters:
    ///   - modelType: The model type
    ///   - id: The model ID
    public func trackAccess<T: ORMTable>(for modelType: T.Type, id: T.IDType) {
        let tableName = T.tableName
        let idString = String(describing: id)
        
        if self.accessTracker[tableName] != nil {
            self.accessTracker[tableName]?[idString] = Date()
        }
    }
    
    /// Enforce model limits after insertion operations
    /// - Parameters:
    ///   - modelType: The model type that was inserted
    ///   - reason: The reason for enforcement (default: limitExceeded)
    /// - Returns: Result indicating success or failure
    public func enforceLimits<T: ORMTable>(
        for modelType: T.Type, 
        reason: ModelRemovalReason = .limitExceeded
    ) async -> ORMResult<Void> {
        let tableName = T.tableName
        
        guard let limit = self.modelLimits[tableName], limit.enabled else {
            return .success(())
        }
        
        // Count current models
        let countResult = await self.database.query(
            "SELECT COUNT(*) as count FROM \(tableName)",
            bindings: []
        )
        
        switch countResult {
        case .success(let rows):
            guard let row = rows.first,
                  case .integer(let currentCount) = row["count"] else {
                return .failure(.invalidData(reason: "Failed to get model count for \(tableName)"))
            }
            
            let excessCount = Int(currentCount) - limit.maxCount
            if excessCount > 0 {
                let removalCount = max(excessCount, limit.batchSize)
                return await self.removeExcessModels(
                    modelType: modelType,
                    count: removalCount,
                    strategy: limit.removalStrategy,
                    reason: reason
                )
            }
            
            return .success(())
            
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Manually enforce model limits for a specific model type
    /// - Parameters:
    ///   - modelType: The model type
    ///   - reason: The reason for enforcement (default: manualEnforcement)
    /// - Returns: Result indicating success or failure
    public func manuallyEnforceLimits<T: ORMTable>(
        for modelType: T.Type,
        reason: ModelRemovalReason = .manualEnforcement
    ) async -> ORMResult<Void> {
        return await self.enforceLimits(for: modelType, reason: reason)
    }
    
    /// Remove excess models based on the configured strategy
    private func removeExcessModels<T: ORMTable>(
        modelType: T.Type,
        count: Int,
        strategy: ModelRemovalStrategy,
        reason: ModelRemovalReason
    ) async -> ORMResult<Void> {
        let tableName = T.tableName
        
        // Build query based on removal strategy
        let sql: String
        let bindings: [SQLiteValue]
        
        switch strategy {
        case .fifo:
            // Remove oldest by creation time (assuming createdAt exists) or ID
            if await self.hasColumn(table: tableName, column: "createdAt") {
                sql = "DELETE FROM \(tableName) WHERE id IN (SELECT id FROM \(tableName) ORDER BY createdAt ASC LIMIT ?)"
            } else {
                sql = "DELETE FROM \(tableName) WHERE id IN (SELECT id FROM \(tableName) ORDER BY id ASC LIMIT ?)"
            }
            bindings = [.integer(Int64(count))]
            
        case .lifo:
            // Remove newest by creation time or ID
            if await self.hasColumn(table: tableName, column: "createdAt") {
                sql = "DELETE FROM \(tableName) WHERE id IN (SELECT id FROM \(tableName) ORDER BY createdAt DESC LIMIT ?)"
            } else {
                sql = "DELETE FROM \(tableName) WHERE id IN (SELECT id FROM \(tableName) ORDER BY id DESC LIMIT ?)"
            }
            bindings = [.integer(Int64(count))]
            
        case .lru:
            // Remove least recently used based on access tracking
            let accessData = self.accessTracker[tableName] ?? [:]
            if accessData.isEmpty {
                // Fallback to FIFO if no access data
                return await self.removeExcessModels(modelType: modelType, count: count, strategy: .fifo, reason: reason)
            }
            
            let sortedIds = accessData.keys.sorted { id1, id2 in
                let date1 = accessData[id1] ?? Date.distantPast
                let date2 = accessData[id2] ?? Date.distantPast
                return date1 < date2
            }
            
            let idsToRemove = Array(sortedIds.prefix(count))
            let placeholders = Array(repeating: "?", count: idsToRemove.count).joined(separator: ", ")
            sql = "DELETE FROM \(tableName) WHERE id IN (\(placeholders))"
            bindings = idsToRemove.map { .text($0) }
            
        case .mru:
            // Remove most recently used based on access tracking
            let accessData = self.accessTracker[tableName] ?? [:]
            if accessData.isEmpty {
                // Fallback to LIFO if no access data
                return await self.removeExcessModels(modelType: modelType, count: count, strategy: .lifo, reason: reason)
            }
            
            let sortedIds = accessData.keys.sorted { id1, id2 in
                let date1 = accessData[id1] ?? Date.distantPast
                let date2 = accessData[id2] ?? Date.distantPast
                return date1 > date2
            }
            
            let idsToRemove = Array(sortedIds.prefix(count))
            let placeholders = Array(repeating: "?", count: idsToRemove.count).joined(separator: ", ")
            sql = "DELETE FROM \(tableName) WHERE id IN (\(placeholders))"
            bindings = idsToRemove.map { .text($0) }
            
        case .random:
            // Remove random models
            sql = "DELETE FROM \(tableName) WHERE id IN (SELECT id FROM \(tableName) ORDER BY RANDOM() LIMIT ?)"
            bindings = [.integer(Int64(count))]
            
        case .smallestFirst:
            // Remove models with smallest ID values
            sql = "DELETE FROM \(tableName) WHERE id IN (SELECT id FROM \(tableName) ORDER BY id ASC LIMIT ?)"
            bindings = [.integer(Int64(count))]
            
        case .largestFirst:
            // Remove models with largest ID values
            sql = "DELETE FROM \(tableName) WHERE id IN (SELECT id FROM \(tableName) ORDER BY id DESC LIMIT ?)"
            bindings = [.integer(Int64(count))]
        }
        
        // Execute the deletion
        let deleteResult = await self.database.execute(sql, bindings: bindings)
        switch deleteResult {
        case .success(let rowsAffected):
            let removedCount = Int(rowsAffected)
            
            // Clean up access tracking for removed models
            if strategy == .lru || strategy == .mru {
                // We would need to query which IDs were actually deleted for precise cleanup
                // For now, we'll do a bulk cleanup periodically
            }
            
            // TODO: Clean up disk storage for removed models if needed
            // This would require querying the deleted models before deletion
            
            // Create removal info for callbacks
            let removalInfo = ModelRemovalInfo(
                tableName: tableName,
                removedCount: removedCount,
                removalStrategy: strategy,
                reason: reason
            )
            
            // Notify Combine subscribers about the changes
            if let changeNotifier = self.changeNotifier {
                await changeNotifier.notifyChange(for: tableName)
            }
            
            // Execute callbacks
            await self.executeRemovalCallbacks(removalInfo: removalInfo)
            
            return .success(())
            
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Execute removal callbacks for a given removal event
    private func executeRemovalCallbacks(removalInfo: ModelRemovalInfo) async {
        // Execute table-specific callback
        if let tableCallback = self.tableRemovalCallbacks[removalInfo.tableName] {
            await tableCallback(removalInfo)
        }
        
        // Execute global callback
        if let globalCallback = self.globalRemovalCallback {
            await globalCallback(removalInfo)
        }
    }
    
    /// Check if a table has a specific column
    private func hasColumn(table: String, column: String) async -> Bool {
        let result = await self.database.query(
            "PRAGMA table_info(\(table))",
            bindings: []
        )
        
        switch result {
        case .success(let rows):
            return rows.contains { row in
                if case .text(let columnName) = row["name"] {
                    return columnName == column
                }
                return false
            }
        case .failure:
            return false
        }
    }
    
    /// Get statistics about model limits
    /// - Returns: Dictionary of table names to their current count and limit
    public func getStatistics() async -> [String: ModelLimitStatistics] {
        var statistics: [String: ModelLimitStatistics] = [:]
        
        for (tableName, limit) in self.modelLimits {
            let countResult = await self.database.query(
                "SELECT COUNT(*) as count FROM \(tableName)",
                bindings: []
            )
            
            let currentCount: Int
            switch countResult {
            case .success(let rows):
                if let row = rows.first,
                   case .integer(let count) = row["count"] {
                    currentCount = Int(count)
                } else {
                    currentCount = 0
                }
            case .failure:
                currentCount = 0
            }
            
            statistics[tableName] = ModelLimitStatistics(
                tableName: tableName,
                currentCount: currentCount,
                maxCount: limit.maxCount,
                removalStrategy: limit.removalStrategy,
                enabled: limit.enabled,
                utilizationPercentage: limit.maxCount > 0 ? Double(currentCount) / Double(limit.maxCount) * 100 : 0
            )
        }
        
        return statistics
    }
    
    /// Cleanup access tracking data for better memory management
    /// Removes entries older than the specified threshold
    /// - Parameter olderThan: Time interval to consider entries as old (default: 30 days)
    public func cleanupAccessTracking(olderThan timeInterval: TimeInterval = 30 * 24 * 60 * 60) {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        
        for (tableName, var accessData) in self.accessTracker {
            let keysToRemove = accessData.compactMap { (key, date) in
                date < cutoffDate ? key : nil
            }
            
            for key in keysToRemove {
                accessData.removeValue(forKey: key)
            }
            
            self.accessTracker[tableName] = accessData
        }
    }
}

/// Statistics about model limits for a specific table
public struct ModelLimitStatistics: Sendable {
    public let tableName: String
    public let currentCount: Int
    public let maxCount: Int
    public let removalStrategy: ModelRemovalStrategy
    public let enabled: Bool
    public let utilizationPercentage: Double
    
    /// Whether the table is approaching its limit (>= 80% utilization)
    public var isApproachingLimit: Bool {
        utilizationPercentage >= 80.0
    }
    
    /// Whether the table has exceeded its limit
    public var hasExceededLimit: Bool {
        enabled && currentCount > maxCount
    }
} 