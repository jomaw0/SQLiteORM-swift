import Foundation

// MARK: - Simple Sync for All ORMTable Types

/// Conflict resolution strategy for sync operations
public enum ConflictResolution: Sendable {
    case serverWins           // Server data always takes precedence (default)
    case localWins            // Local data always takes precedence
    case newestWins           // Most recently modified data wins
    case askUser              // Trigger callback for user decision
    case custom(@Sendable (any ORMTable, any ORMTable) -> any ORMTable)
}

/// Simple sync changes result
public struct SyncChanges<T: ORMTable>: Sendable {
    public var inserted: [T]     // New items from server
    public var updated: [T]      // Items that were updated
    public var removed: [T]      // Items that were removed locally
    public var conflicts: Int    // Number of conflicts resolved
    
    public var totalChanges: Int {
        return inserted.count + updated.count + removed.count
    }
    
    public init(inserted: [T] = [], updated: [T] = [], removed: [T] = [], conflicts: Int = 0) {
        self.inserted = inserted
        self.updated = updated
        self.removed = removed
        self.conflicts = conflicts
    }
}

/// Simple sync options
public struct SyncOptions: Sendable {
    public let conflictResolution: ConflictResolution
    public let deleteRemoved: Bool  // Whether to delete items not in server data
    
    public init(
        conflictResolution: ConflictResolution = .serverWins,
        deleteRemoved: Bool = false
    ) {
        self.conflictResolution = conflictResolution
        self.deleteRemoved = deleteRemoved
    }
    
    public static let `default` = SyncOptions()
}

// MARK: - ORMTable Sync Extension

/// Add sync methods to all ORMTable types
public extension ORMTable {
    
    /// SIMPLEST SYNC METHOD - server wins by default
    /// - Parameters:
    ///   - serverData: Array of models from server
    ///   - orm: ORM instance for database operations
    /// - Returns: Result with sync changes
    static func sync(
        with serverData: [Self],
        orm: ORM
    ) async -> Result<SyncChanges<Self>, Error> {
        return await sync(
            with: serverData,
            orm: orm,
            conflictResolution: .serverWins,
            changeCallback: nil
        )
    }
    
    /// Sync with conflict resolution
    /// - Parameters:
    ///   - serverData: Array of models from server
    ///   - orm: ORM instance for database operations
    ///   - conflictResolution: How to handle conflicts
    ///   - changeCallback: Optional callback to observe changes
    /// - Returns: Result with sync changes
    static func sync(
        with serverData: [Self],
        orm: ORM,
        conflictResolution: ConflictResolution = .serverWins,
        changeCallback: ((SyncChanges<Self>) async -> Void)? = nil
    ) async -> Result<SyncChanges<Self>, Error> {
        
        do {
            let repository = await orm.repository(for: Self.self)
            
            // Get all local data
            let localResult = await repository.findAll()
            guard case .success(let localData) = localResult else {
                if case .failure(let error) = localResult {
                    return .failure(error)
                }
                return .failure(SyncError.localDataError)
            }
            
            // Perform the sync
            let changes = await performSync(
                local: localData,
                server: serverData,
                repository: repository,
                conflictResolution: conflictResolution
            )
            
            // Notify observer if provided
            if let callback = changeCallback {
                await callback(changes)
            }
            
            return .success(changes)
            
        } catch {
            return .failure(error)
        }
    }
    
    /// Get local changes that need to be uploaded
    static func getLocalChanges(orm: ORM) async -> Result<[Self], Error> {
        let repository = await orm.repository(for: Self.self)
        let dirtyQuery = ORMQueryBuilder<Self>().where("isDirty", .equal, true)
        let result = await repository.findAll(query: dirtyQuery)
        return result.mapError { $0 as Error }
    }
    
    /// Mark models as synced after successful upload
    static func markAsSynced(_ models: [Self], orm: ORM) async -> Result<Void, Error> {
        let repository = await orm.repository(for: Self.self)
        
        for model in models {
            var syncedModel = model
            syncedModel.isDirty = false
            syncedModel.syncStatus = .synced
            syncedModel.lastSyncTimestamp = Date()
            
            let result = await repository.update(syncedModel)
            if case .failure(let error) = result {
                return .failure(error as Error)
            }
        }
        
        return .success(())
    }
}

// MARK: - Core Sync Logic

extension ORMTable {
    
    /// Perform the actual synchronization logic
    private static func performSync(
        local: [Self],
        server: [Self],
        repository: Repository<Self>,
        conflictResolution: ConflictResolution
    ) async -> SyncChanges<Self> {
        
        var changes = SyncChanges<Self>()
        
        // Create lookup maps for efficient comparison
        let localByID = createLookupMap(local)
        let serverByID = createLookupMap(server)
        
        // Process server models
        for serverModel in server {
            if let localModel = findMatchingLocal(serverModel, in: localByID) {
                // Model exists locally - check for conflicts
                if hasConflict(local: localModel, server: serverModel) {
                    // Handle conflict
                    let resolved = await resolveConflict(
                        local: localModel,
                        server: serverModel,
                        resolution: conflictResolution,
                        repository: repository
                    )
                    
                    changes.conflicts += 1
                    changes.updated.append(resolved)
                    
                } else if !localModel.isDirty {
                    // No conflict, safe to update
                    let updated = await updateWithServerData(
                        local: localModel,
                        server: serverModel,
                        repository: repository
                    )
                    changes.updated.append(updated)
                }
                // If local is dirty but no conflict, keep local version (no changes)
                
            } else {
                // New model from server
                let inserted = await insertServerModel(serverModel, repository: repository)
                changes.inserted.append(inserted)
            }
        }
        
        return changes
    }
    
    /// Create lookup map for efficient model matching
    private static func createLookupMap(_ models: [Self]) -> [String: Self] {
        var map: [String: Self] = [:]
        
        for model in models {
            // Prefer server ID for matching, fallback to local ID
            if let serverID = model.serverID {
                map[serverID] = model
            } else {
                map[String(describing: model.id)] = model
            }
        }
        
        return map
    }
    
    /// Find matching local model for server model
    private static func findMatchingLocal(_ serverModel: Self, in localMap: [String: Self]) -> Self? {
        // Try server ID first
        if let serverID = serverModel.serverID, let match = localMap[serverID] {
            return match
        }
        
        // Fallback to local ID
        let idString = String(describing: serverModel.id)
        return localMap[idString]
    }
    
    /// Check if there's a conflict between local and server models
    private static func hasConflict(local: Self, server: Self) -> Bool {
        // If local has changes and fingerprints differ, it's a conflict
        return local.isDirty && local.conflictFingerprint != server.conflictFingerprint
    }
    
    /// Resolve conflict between local and server models
    private static func resolveConflict(
        local: Self,
        server: Self,
        resolution: ConflictResolution,
        repository: Repository<Self>
    ) async -> Self {
        
        let resolved: Self
        
        switch resolution {
        case .serverWins:
            resolved = await applyServerData(to: local, from: server, repository: repository)
            
        case .localWins:
            resolved = local // Keep local version as-is
            
        case .newestWins:
            let localTime = local.lastSyncTimestamp ?? Date.distantPast
            let serverTime = server.lastSyncTimestamp ?? Date.distantPast
            
            if serverTime > localTime {
                resolved = await applyServerData(to: local, from: server, repository: repository)
            } else {
                resolved = local
            }
            
        case .askUser:
            // Fallback to server wins if no resolver provided
            resolved = await applyServerData(to: local, from: server, repository: repository)
            
        case .custom(let customResolver):
            if let customResolved = customResolver(local, server) as? Self {
                var updated = customResolved
                updated.isDirty = false
                updated.syncStatus = .synced
                updated.lastSyncTimestamp = Date()
                let _ = await repository.update(updated)
                resolved = updated
            } else {
                // Fallback to server wins if custom resolver fails
                resolved = await applyServerData(to: local, from: server, repository: repository)
            }
        }
        
        return resolved
    }
    
    /// Apply server data to local model while preserving local ID
    private static func applyServerData(
        to local: Self,
        from server: Self,
        repository: Repository<Self>
    ) async -> Self {
        
        var updated = server
        updated.id = local.id // Preserve local ID
        updated.isDirty = false
        updated.syncStatus = .synced
        updated.lastSyncTimestamp = Date()
        
        let _ = await repository.update(updated)
        return updated
    }
    
    /// Update local model with server data (no conflict)
    private static func updateWithServerData(
        local: Self,
        server: Self,
        repository: Repository<Self>
    ) async -> Self {
        
        var updated = server
        updated.id = local.id // Preserve local ID
        updated.isDirty = false
        updated.syncStatus = .synced
        updated.lastSyncTimestamp = Date()
        
        let _ = await repository.update(updated)
        return updated
    }
    
    /// Insert new server model
    private static func insertServerModel(
        _ server: Self,
        repository: Repository<Self>
    ) async -> Self {
        
        var newModel = server
        newModel.isDirty = false
        newModel.syncStatus = .synced
        newModel.lastSyncTimestamp = Date()
        
        let _ = await repository.insert(&newModel)
        return newModel
    }
}

// MARK: - Sync Errors

public enum SyncError: Error {
    case localDataError
    case conflictResolutionError
    case repositoryError(String)
    case invalidServerData
}