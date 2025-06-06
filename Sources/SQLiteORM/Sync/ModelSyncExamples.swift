import Foundation

// MARK: - Model-Centric Sync Examples

/// Examples showing the clean, model-centric sync API
public struct ModelSyncExamples {
    
    // MARK: - Basic Usage
    
    /// Simplest sync - just call sync on the model type
    public static func basicModelSync() async {
        let orm = createFileORM(filename: "app.sqlite")
        let _ = await orm.openAndCreateTables(User.self)
        
        // You have server data from wherever
        let serverUsers = [
            User(id: 1, username: "john", email: "john@example.com"),
            User(id: 2, username: "jane", email: "jane@example.com")
        ]
        
        // SIMPLEST SYNC - one method call on the model
        let result = await User.sync(serverData: serverUsers, orm: orm)
        
        switch result {
        case .success(let changes):
            print("✅ Sync complete:")
            print("   Inserted: \(changes.inserted.count)")
            print("   Updated: \(changes.updated.count)")
            print("   Removed: \(changes.removed.count)")
            print("   Conflicts: \(changes.conflicts.count)")
        case .failure(let error):
            print("❌ Sync failed: \(error)")
        }
    }
    
    // MARK: - Conflict Resolution
    
    /// Different conflict resolution strategies
    public static func conflictResolutionExamples() async {
        let orm = createFileORM(filename: "app.sqlite")
        let serverUsers = [/* your data */]
        
        // Server always wins (default)
        await User.sync(
            serverData: serverUsers,
            orm: orm,
            conflictResolution: .serverWins
        )
        
        // Local always wins
        await User.sync(
            serverData: serverUsers,
            orm: orm,
            conflictResolution: .localWins
        )
        
        // Newest modification wins
        await User.sync(
            serverData: serverUsers,
            orm: orm,
            conflictResolution: .newestWins
        )
        
        // Ask user for each conflict
        let result = await User.sync(
            serverData: serverUsers,
            orm: orm,
            conflictResolution: .askUser,
            conflictResolver: { localUser, serverUser in
                // In real app, show UI to user
                print("Conflict detected:")
                print("Local: \(localUser.username) - \(localUser.email)")
                print("Server: \(serverUser.username) - \(serverUser.email)")
                
                // For this example, pick server
                return serverUser
            }
        )
        
        // Custom conflict resolution
        await User.sync(
            serverData: serverUsers,
            orm: orm,
            conflictResolution: .custom { local, server in
                // Your custom logic
                if local.email.contains("@company.com") {
                    return local  // Keep company emails
                } else {
                    return server // Use server for others
                }
            }
        )
    }
    
    // MARK: - Change Callbacks
    
    /// Monitor what changes during sync
    public static func changeCallbackExample() async {
        let orm = createFileORM(filename: "app.sqlite")
        let serverUsers = [/* your data */]
        
        let result = await User.sync(
            serverData: serverUsers,
            orm: orm,
            changeCallback: { changes in
                // Get notified of all changes
                print("📊 Sync changes:")
                
                if !changes.inserted.isEmpty {
                    print("➕ Inserted \(changes.inserted.count) users:")
                    for user in changes.inserted {
                        print("   - \(user.username) (\(user.email))")
                    }
                }
                
                if !changes.updated.isEmpty {
                    print("📝 Updated \(changes.updated.count) users:")
                    for user in changes.updated {
                        print("   - \(user.username) (\(user.email))")
                    }
                }
                
                if !changes.removed.isEmpty {
                    print("🗑️ Removed \(changes.removed.count) users:")
                    for user in changes.removed {
                        print("   - \(user.username) (\(user.email))")
                    }
                }
                
                if !changes.conflicts.isEmpty {
                    print("⚠️ Resolved \(changes.conflicts.count) conflicts:")
                    for conflict in changes.conflicts {
                        print("   - \(conflict.local.username) vs \(conflict.server.username)")
                        print("     Resolution: \(conflict.resolution)")
                    }
                }
            }
        )
    }
    
    // MARK: - Advanced Options
    
    /// Sync with advanced options
    public static func advancedSyncOptions() async {
        let orm = createFileORM(filename: "app.sqlite")
        let serverUsers = [/* your data */]
        
        let options = SyncOptions(
            conflictResolution: .newestWins,
            deleteRemoved: true,  // Delete local items not in server data
            batchSize: 50         // Process in smaller batches
        )
        
        let result = await User.sync(
            serverData: serverUsers,
            orm: orm,
            options: options,
            conflictResolver: { local, server in
                // Custom resolver for .askUser conflicts
                return server
            },
            changeCallback: { changes in
                // Monitor changes
                print("Total changes: \(changes.totalChanges)")
            }
        )
    }
    
    // MARK: - Two-Way Sync Pattern
    
    /// Complete two-way sync with upload and download
    public static func twoWaySync() async {
        let orm = createFileORM(filename: "app.sqlite")
        
        // === DOWNLOAD PHASE ===
        
        // 1. Get server data (your API call)
        let serverUsers = await fetchUsersFromAPI()
        
        // 2. Sync with local database
        let downloadResult = await User.sync(
            serverData: serverUsers,
            orm: orm,
            conflictResolution: .newestWins,
            changeCallback: { changes in
                print("Downloaded: \(changes.inserted.count + changes.updated.count) users")
            }
        )
        
        // === UPLOAD PHASE ===
        
        // 3. Get local changes
        let localChangesResult = await User.getLocalChanges(orm: orm)
        
        switch localChangesResult {
        case .success(let localChanges):
            if !localChanges.isEmpty {
                // 4. Upload to server (your API call)
                let uploadedUsers = await uploadUsersToAPI(localChanges)
                
                // 5. Mark as synced
                let _ = await User.markAsSynced(uploadedUsers, orm: orm)
                print("Uploaded: \(uploadedUsers.count) users")
            }
        case .failure(let error):
            print("Failed to get local changes: \(error)")
        }
    }
    
    // MARK: - Real-World Scenarios
    
    /// E-commerce sync scenario
    public static func ecommerceSync() async {
        let orm = createFileORM(filename: "ecommerce.sqlite")
        let _ = await orm.openAndCreateTables(Product.self, Order.self, Customer.self)
        
        // Download products (server wins - products are managed centrally)
        let serverProducts = await fetchProductsFromAPI()
        await Product.sync(
            serverData: serverProducts,
            orm: orm,
            conflictResolution: .serverWins,
            changeCallback: { changes in
                print("Product catalog updated: \(changes.totalChanges) changes")
            }
        )
        
        // Download customers (server wins - customer data is authoritative)
        let serverCustomers = await fetchCustomersFromAPI()
        await Customer.sync(
            serverData: serverCustomers,
            orm: orm,
            conflictResolution: .serverWins
        )
        
        // Upload orders (local wins - orders created locally have priority)
        let localOrders = await Order.getLocalChanges(orm: orm)
        if case .success(let orders) = localOrders, !orders.isEmpty {
            let uploadedOrders = await uploadOrdersToAPI(orders)
            await Order.markAsSynced(uploadedOrders, orm: orm)
        }
    }
    
    /// Social media sync scenario
    public static func socialMediaSync() async {
        let orm = createFileORM(filename: "social.sqlite")
        
        // Posts: bidirectional sync with conflict resolution
        let serverPosts = await fetchPostsFromAPI()
        await Post.sync(
            serverData: serverPosts,
            orm: orm,
            conflictResolution: .askUser,
            conflictResolver: { localPost, serverPost in
                // In real app, show UI for user to choose
                print("Post conflict: '\(localPost.title)' vs '\(serverPost.title)'")
                return serverPost // For example
            },
            changeCallback: { changes in
                // Notify user of post updates
                if changes.conflicts.count > 0 {
                    showNotification("Resolved \(changes.conflicts.count) post conflicts")
                }
            }
        )
        
        // Comments: newest wins
        let serverComments = await fetchCommentsFromAPI()
        await Comment.sync(
            serverData: serverComments,
            orm: orm,
            conflictResolution: .newestWins
        )
    }
    
    // MARK: - Batch Processing
    
    /// Handle large datasets with batching
    public static func largeBatchSync() async {
        let orm = createFileORM(filename: "app.sqlite")
        
        // Get large dataset from server
        let allServerUsers = await fetchAllUsersFromAPI() // Could be thousands
        
        // Sync in batches to avoid memory issues
        let batchSize = 100
        let batches = allServerUsers.chunked(into: batchSize)
        
        var totalChanges = 0
        
        for (index, batch) in batches.enumerated() {
            print("Processing batch \(index + 1) of \(batches.count)...")
            
            let result = await User.sync(
                serverData: batch,
                orm: orm,
                conflictResolution: .serverWins,
                changeCallback: { changes in
                    totalChanges += changes.totalChanges
                    print("  Batch \(index + 1): \(changes.totalChanges) changes")
                }
            )
            
            // Optional: pause between batches
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        print("✅ Large sync complete: \(totalChanges) total changes")
    }
    
    // MARK: - Error Handling
    
    /// Comprehensive error handling
    public static func errorHandlingExample() async {
        let orm = createFileORM(filename: "app.sqlite")
        let serverUsers = [/* your data */]
        
        let result = await User.sync(
            serverData: serverUsers,
            orm: orm,
            conflictResolution: .askUser,
            conflictResolver: { local, server in
                // Handle conflict resolution errors
                do {
                    return try await resolveUserConflict(local: local, server: server)
                } catch {
                    print("⚠️ Conflict resolution failed: \(error)")
                    return server // Fallback to server
                }
            },
            changeCallback: { changes in
                // Log all changes for debugging
                logSyncChanges(changes)
            }
        )
        
        switch result {
        case .success(let changes):
            if changes.conflicts.count > 0 {
                print("⚠️ Sync completed with \(changes.conflicts.count) conflicts")
                // Maybe prompt user to review conflicts
                await showConflictSummary(changes.conflicts)
            } else {
                print("✅ Clean sync: \(changes.totalChanges) changes")
            }
            
        case .failure(let error):
            print("❌ Sync failed: \(error)")
            
            // Handle different error types
            switch error as? SyncError {
            case .localDataError:
                print("Local database issue - check permissions")
            case .conflictResolutionError:
                print("Conflict resolution failed - using defaults")
            case .repositoryError(let message):
                print("Repository error: \(message)")
            case .invalidServerData:
                print("Server data is invalid - check API response")
            default:
                print("Unknown sync error: \(error)")
            }
        }
    }
    
    // MARK: - Performance Monitoring
    
    /// Monitor sync performance
    public static func performanceMonitoring() async {
        let orm = createFileORM(filename: "app.sqlite")
        let serverUsers = await fetchUsersFromAPI()
        
        let startTime = Date()
        
        let result = await User.sync(
            serverData: serverUsers,
            orm: orm,
            changeCallback: { changes in
                let duration = Date().timeIntervalSince(startTime)
                let rate = Double(changes.totalChanges) / duration
                
                print("📊 Sync Performance:")
                print("   Duration: \(String(format: "%.2f", duration))s")
                print("   Changes: \(changes.totalChanges)")
                print("   Rate: \(String(format: "%.1f", rate)) changes/sec")
                
                // Log performance metrics
                logPerformanceMetrics(
                    modelType: "User",
                    duration: duration,
                    changes: changes.totalChanges,
                    conflicts: changes.conflicts.count
                )
            }
        )
    }
}

// MARK: - Mock Functions (for examples)

private func fetchUsersFromAPI() async -> [User] {
    return [
        User(id: 1, username: "john", email: "john@example.com"),
        User(id: 2, username: "jane", email: "jane@example.com")
    ]
}

private func uploadUsersToAPI(_ users: [User]) async -> [User] {
    return users.map { user in
        var updated = user
        updated.serverID = "server_\(user.id)"
        return updated
    }
}

private func fetchProductsFromAPI() async -> [Product] {
    return [Product(id: 1, name: "iPhone", price: 999.0)]
}

private func fetchCustomersFromAPI() async -> [Customer] {
    return [Customer(id: 1, name: "John Doe")]
}

private func uploadOrdersToAPI(_ orders: [Order]) async -> [Order] {
    return orders
}

private func fetchPostsFromAPI() async -> [Post] {
    return [Post(id: 1, title: "Hello World", content: "First post")]
}

private func fetchCommentsFromAPI() async -> [Comment] {
    return [Comment(id: 1, content: "Nice post!", postId: 1, authorId: 1)]
}

private func fetchAllUsersFromAPI() async -> [User] {
    return (1...1000).map { i in
        User(id: i, username: "user\(i)", email: "user\(i)@example.com")
    }
}

private func resolveUserConflict(local: User, server: User) async throws -> User {
    // Mock conflict resolution
    return server
}

private func showNotification(_ message: String) {
    print("🔔 \(message)")
}

private func logSyncChanges<T: SyncableModel>(_ changes: SyncChanges<T>) {
    print("📝 Logging sync changes: \(changes.totalChanges) total")
}

private func showConflictSummary<T: SyncableModel>(_ conflicts: [SyncConflict<T>]) async {
    print("📋 Conflict Summary: \(conflicts.count) conflicts resolved")
}

private func logPerformanceMetrics(modelType: String, duration: TimeInterval, changes: Int, conflicts: Int) {
    print("📊 Performance logged for \(modelType): \(duration)s, \(changes) changes, \(conflicts) conflicts")
}

// MARK: - Model Extensions for Examples

extension User {
    init(id: Int, username: String, email: String) {
        self.init()
        self.id = id
        self.username = username
        self.email = email
    }
}

extension Product {
    init(id: Int, name: String, price: Double) {
        self.init()
        self.id = id
        self.name = name
        self.price = price
    }
}

extension Customer {
    init(id: Int, name: String) {
        self.init()
        self.id = id
        self.name = name
    }
}

extension Post {
    init(id: Int, title: String, content: String) {
        self.init()
        self.id = id
        self.title = title
        self.content = content
    }
}

extension Comment {
    init(id: Int, content: String, postId: Int, authorId: Int) {
        self.init()
        self.id = id
        self.content = content
        self.postId = postId
        self.authorId = authorId
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}