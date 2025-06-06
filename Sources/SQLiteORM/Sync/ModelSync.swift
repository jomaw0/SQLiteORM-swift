import Foundation

// MARK: - Model-Centric Sync System

/// Conflict resolution strategy for sync operations
public enum ConflictResolution {
    case serverWins           // Server data always takes precedence
    case localWins            // Local data always takes precedence
    case newestWins           // Most recently modified data wins
    case askUser              // Trigger callback for user decision
    case custom((any SyncableModel, any SyncableModel) -> any SyncableModel)
}

/// Detailed information about sync changes
public struct SyncChanges<T: SyncableModel> {
    public let inserted: [T]     // New items from server
    public let updated: [T]      // Items that were updated
    public let removed: [T]      // Items that were removed locally
    public let conflicts: [SyncConflict<T>]  // Conflicts that were resolved
    
    public var totalChanges: Int {
        return inserted.count + updated.count + removed.count
    }
    
    public init(inserted: [T] = [], updated: [T] = [], removed: [T] = [], conflicts: [SyncConflict<T>] = []) {
        self.inserted = inserted
        self.updated = updated
        self.removed = removed
        self.conflicts = conflicts
    }
}

/// Represents a conflict between local and server data
public struct SyncConflict<T: SyncableModel> {
    public let local: T
    public let server: T
    public let resolved: T
    public let resolution: ConflictResolution
    
    public init(local: T, server: T, resolved: T, resolution: ConflictResolution) {
        self.local = local
        self.server = server
        self.resolved = resolved
        self.resolution = resolution
    }
}

/// Options for sync behavior
public struct SyncOptions {
    public let conflictResolution: ConflictResolution
    public let deleteRemoved: Bool  // Whether to delete items not in server data
    public let batchSize: Int       // Process in batches for large datasets
    
    public init(
        conflictResolution: ConflictResolution = .serverWins,
        deleteRemoved: Bool = false,
        batchSize: Int = 100
    ) {
        self.conflictResolution = conflictResolution
        self.deleteRemoved = deleteRemoved
        self.batchSize = batchSize
    }
    
    public static let `default` = SyncOptions()
}

/// Callback for handling conflicts when resolution is .askUser
public typealias ConflictResolver<T: SyncableModel> = (T, T) async -> T

/// Callback for observing sync changes
public typealias SyncChangeCallback<T: SyncableModel> = (SyncChanges<T>) async -> Void

// MARK: - SyncableModel Extensions

/// Add sync method to all SyncableModel types
public extension SyncableModel {
    
    /// Sync this model type with server data
    /// - Parameters:
    ///   - serverData: Array of models from server
    ///   - orm: ORM instance for database operations
    ///   - options: Sync options including conflict resolution
    ///   - conflictResolver: Optional callback for manual conflict resolution
    ///   - changeCallback: Optional callback to observe changes
    /// - Returns: Result with sync changes
    static func sync(
        serverData: [Self],
        orm: ORM,
        options: SyncOptions = .default,
        conflictResolver: ConflictResolver<Self>? = nil,
        changeCallback: SyncChangeCallback<Self>? = nil
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
                options: options,
                conflictResolver: conflictResolver
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
    
    /// Simplified sync with just conflict resolution strategy
    static func sync(
        serverData: [Self],
        orm: ORM,
        conflictResolution: ConflictResolution = .serverWins,
        changeCallback: SyncChangeCallback<Self>? = nil
    ) async -> Result<SyncChanges<Self>, Error> {
        
        let options = SyncOptions(conflictResolution: conflictResolution)
        return await sync(
            serverData: serverData,
            orm: orm,
            options: options,
            changeCallback: changeCallback
        )
    }
    
    /// Get local changes that need to be uploaded
    static func getLocalChanges(orm: ORM) async -> Result<[Self], Error> {
        let repository = await orm.repository(for: Self.self)
        let dirtyQuery = ORMQueryBuilder<Self>().where("isDirty", .equal, true)
        return await repository.findAll(query: dirtyQuery)
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
                return .failure(error)
            }
        }
        
        return .success(())
    }
}

// MARK: - Core Sync Logic

extension SyncableModel {
    
    /// Perform the actual synchronization logic
    private static func performSync(
        local: [Self],
        server: [Self],
        repository: Repository<Self>,
        options: SyncOptions,
        conflictResolver: ConflictResolver<Self>?
    ) async -> SyncChanges<Self> {
        
        var changes = SyncChanges<Self>()
        
        // Create lookup maps for efficient comparison
        let localByID = createLookupMap(local)
        let serverByID = createLookupMap(server)
        
        // Process server models
        for serverModel in server {
            if let localModel = findMatchingLocal(serverModel, in: localByID) {
                // Model exists locally - check for conflicts
                if await hasConflict(local: localModel, server: serverModel) {
                    // Handle conflict
                    let conflict = await resolveConflict(
                        local: localModel,
                        server: serverModel,
                        resolution: options.conflictResolution,
                        resolver: conflictResolver,
                        repository: repository
                    )
                    
                    changes.conflicts.append(conflict)
                    changes.updated.append(conflict.resolved)
                    
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
        
        // Handle items that exist locally but not on server
        if options.deleteRemoved {
            let serverIDs = Set(server.compactMap { getModelIdentifier($0) })
            let localOnlyModels = local.filter { localModel in
                !serverIDs.contains(getModelIdentifier(localModel))
            }
            
            for localModel in localOnlyModels {
                await deleteLocalModel(localModel, repository: repository)
                changes.removed.append(localModel)
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
    
    /// Get unique identifier for model matching
    private static func getModelIdentifier(_ model: Self) -> String {
        return model.serverID ?? String(describing: model.id)
    }
    
    /// Check if there's a conflict between local and server models
    private static func hasConflict(local: Self, server: Self) async -> Bool {
        // If local has changes and fingerprints differ, it's a conflict
        return local.isDirty && local.conflictFingerprint != server.conflictFingerprint
    }
    
    /// Resolve conflict between local and server models
    private static func resolveConflict(
        local: Self,
        server: Self,
        resolution: ConflictResolution,
        resolver: ConflictResolver<Self>?,
        repository: Repository<Self>
    ) async -> SyncConflict<Self> {
        
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
            if let resolver = resolver {
                resolved = await resolver(local, server)
                let _ = await repository.update(resolved)
            } else {
                // Fallback to server wins if no resolver provided
                resolved = await applyServerData(to: local, from: server, repository: repository)
            }
            
        case .custom(let customResolver):
            if let customResolved = customResolver(local, server) as? Self {
                resolved = customResolved
                let _ = await repository.update(resolved)
            } else {
                // Fallback to server wins if custom resolver fails
                resolved = await applyServerData(to: local, from: server, repository: repository)
            }
        }
        
        return SyncConflict(local: local, server: server, resolved: resolved, resolution: resolution)
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
    
    /// Delete local model
    private static func deleteLocalModel(
        _ local: Self,
        repository: Repository<Self>
    ) async {
        
        let _ = await repository.delete(id: local.id)
    }
}

// MARK: - Sync Errors

public enum SyncError: Error {
    case localDataError
    case conflictResolutionError
    case repositoryError(String)
    case invalidServerData
}

// MARK: - Repository Extensions

public extension Repository where T: SyncableModel {
    
    /// Sync this repository's model type with server data
    func sync(
        serverData: [T],
        options: SyncOptions = .default,
        conflictResolver: ConflictResolver<T>? = nil,
        changeCallback: SyncChangeCallback<T>? = nil
    ) async -> Result<SyncChanges<T>, Error> {
        
        // This would need access to the ORM instance
        // For now, recommend using the static method on the model type
        fatalError("Use T.sync(serverData:orm:...) instead - repository needs ORM access")
    }
    
    /// Get models that need to be uploaded
    func getLocalChanges() async -> Result<[T], Error> {
        let dirtyQuery = ORMQueryBuilder<T>().where("isDirty", .equal, true)
        return await findAll(query: dirtyQuery)
    }
    
    /// Mark models as synced after upload
    func markAsSynced(_ models: [T]) async -> Result<Void, Error> {
        for model in models {
            var syncedModel = model
            syncedModel.isDirty = false
            syncedModel.syncStatus = .synced
            syncedModel.lastSyncTimestamp = Date()
            
            let result = await update(syncedModel)
            if case .failure(let error) = result {
                return .failure(error)
            }
        }
        return .success(())
    }
}