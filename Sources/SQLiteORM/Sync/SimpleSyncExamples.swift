import Foundation

// MARK: - Simple Sync Examples (Every Model is Automatically Syncable)

/// Examples showing the ultra-simple sync API where every ORMTable is automatically syncable
public struct SimpleSyncExamples {
    
    // MARK: - Basic Usage (Simplest Possible)
    
    /// The absolute simplest sync - every model has .sync(with:orm:)
    public static func simplestSync() async {
        let orm = createFileORM(filename: "app.sqlite")
        let _ = await orm.openAndCreateTables(User.self)
        
        // You have server data from wherever
        let serverUsers = [
            User(id: 1, username: "john", email: "john@example.com"),
            User(id: 2, username: "jane", email: "jane@example.com")
        ]
        
        // SIMPLEST SYNC - server wins by default
        let result = await User.sync(with: serverUsers, orm: orm)
        
        switch result {
        case .success(let changes):
            print("✅ Sync complete: \(changes.totalChanges) changes")
        case .failure(let error):
            print("❌ Sync failed: \(error)")
        }
    }
    
    // MARK: - Model Definitions (No Special Protocols Needed)
    
    /// Standard ORMTable - automatically gets sync capabilities
    @ORMTable
    struct User: ORMTable {
        typealias IDType = Int
        var id: Int = 0
        var username: String = ""
        var email: String = ""
        var createdAt: Date = Date()
        
        // Sync properties are automatically included in ORMTable!
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int, username: String, email: String) {
            self.id = id
            self.username = username
            self.email = email
            self.createdAt = Date()
        }
    }
    
    /// Another model - automatically syncable
    @ORMTable
    struct Product: ORMTable {
        typealias IDType = Int
        var id: Int = 0
        var name: String = ""
        var price: Double = 0.0
        var category: String = ""
        
        // Sync properties (required by ORMTable)
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int, name: String, price: Double, category: String = "") {
            self.id = id
            self.name = name
            self.price = price
            self.category = category
        }
    }
    
    /// Order model - also automatically syncable
    @ORMTable
    struct Order: ORMTable {
        typealias IDType = Int
        var id: Int = 0
        var customerId: Int = 0
        var total: Double = 0.0
        var orderDate: Date = Date()
        
        // Sync properties (required by ORMTable)
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int, customerId: Int, total: Double) {
            self.id = id
            self.customerId = customerId
            self.total = total
            self.orderDate = Date()
        }
    }
    
    // MARK: - Conflict Resolution Examples
    
    /// Different ways to handle conflicts
    public static func conflictResolutionExamples() async {
        let orm = createFileORM(filename: "app.sqlite")
        let serverUsers = [User(id: 1, username: "john", email: "john@example.com")]
        
        // Server wins (default)
        await User.sync(with: serverUsers, orm: orm)
        
        // Local wins
        await User.sync(with: serverUsers, orm: orm, conflictResolution: .localWins)
        
        // Newest wins
        await User.sync(with: serverUsers, orm: orm, conflictResolution: .newestWins)
        
        // Custom resolution
        await User.sync(
            with: serverUsers,
            orm: orm,
            conflictResolution: .custom { local, server in
                // Your custom logic here
                return server
            }
        )
    }
    
    // MARK: - Change Tracking
    
    /// Monitor what changes during sync
    public static func changeTrackingExample() async {
        let orm = createFileORM(filename: "app.sqlite")
        let serverProducts = [
            Product(id: 1, name: "iPhone", price: 999.0, category: "Electronics"),
            Product(id: 2, name: "MacBook", price: 1999.0, category: "Computers")
        ]
        
        let result = await Product.sync(
            with: serverProducts,
            orm: orm,
            changeCallback: { changes in
                print("📊 Product sync results:")
                print("➕ New products: \(changes.inserted.count)")
                print("📝 Updated products: \(changes.updated.count)")
                print("⚠️ Conflicts resolved: \(changes.conflicts)")
                
                // Log individual changes
                for product in changes.inserted {
                    print("   New: \(product.name) - $\(product.price)")
                }
                
                for product in changes.updated {
                    print("   Updated: \(product.name) - $\(product.price)")
                }
            }
        )
    }
    
    // MARK: - Two-Way Sync Pattern
    
    /// Complete two-way sync workflow
    public static func twoWaySync() async {
        let orm = createFileORM(filename: "app.sqlite")
        let _ = await orm.openAndCreateTables(Order.self)
        
        // === DOWNLOAD PHASE ===
        
        // 1. Get server data (however you fetch it)
        let serverOrders = await fetchOrdersFromAPI()
        
        // 2. Sync with local - server wins for existing orders
        let downloadResult = await Order.sync(
            with: serverOrders,
            orm: orm,
            conflictResolution: .serverWins,
            changeCallback: { changes in
                print("📥 Downloaded: \(changes.totalChanges) order changes")
            }
        )
        
        // === UPLOAD PHASE ===
        
        // 3. Get local changes that need uploading
        let localChanges = await Order.getLocalChanges(orm: orm)
        
        switch localChanges {
        case .success(let orders):
            if !orders.isEmpty {
                // 4. Upload to server (your API call)
                let uploadedOrders = await uploadOrdersToAPI(orders)
                
                // 5. Mark as synced
                let _ = await Order.markAsSynced(uploadedOrders, orm: orm)
                print("📤 Uploaded: \(uploadedOrders.count) orders")
            }
        case .failure(let error):
            print("❌ Failed to get local changes: \(error)")
        }
    }
    
    // MARK: - Real-World Scenarios
    
    /// E-commerce app sync
    public static func ecommerceSync() async {
        let orm = createFileORM(filename: "ecommerce.sqlite")
        let _ = await orm.openAndCreateTables(Product.self, Order.self, User.self)
        
        // Products: server is authoritative
        let serverProducts = await fetchProductsFromAPI()
        await Product.sync(with: serverProducts, orm: orm) // Server wins by default
        
        // Users: bidirectional with newest wins
        let serverUsers = await fetchUsersFromAPI()
        await User.sync(
            with: serverUsers,
            orm: orm,
            conflictResolution: .newestWins
        )
        
        // Orders: upload local changes
        let localOrders = await Order.getLocalChanges(orm: orm)
        if case .success(let orders) = localOrders, !orders.isEmpty {
            let uploaded = await uploadOrdersToAPI(orders)
            await Order.markAsSynced(uploaded, orm: orm)
        }
    }
    
    /// Content app sync (download only)
    public static func contentAppSync() async {
        let orm = createFileORM(filename: "content.sqlite")
        
        // Articles from CMS - server always wins
        let articles = await fetchArticlesFromCMS()
        await Article.sync(with: articles, orm: orm) // Default: server wins
        
        // Categories from CMS
        let categories = await fetchCategoriesFromCMS()
        await Category.sync(with: categories, orm: orm)
    }
    
    /// Social media app sync
    public static func socialMediaSync() async {
        let orm = createFileORM(filename: "social.sqlite")
        
        // Posts: handle conflicts carefully
        let serverPosts = await fetchPostsFromAPI()
        await Post.sync(
            with: serverPosts,
            orm: orm,
            conflictResolution: .newestWins,
            changeCallback: { changes in
                if changes.conflicts > 0 {
                    print("⚠️ Resolved \(changes.conflicts) post conflicts")
                }
            }
        )
        
        // Comments: server wins for consistency
        let serverComments = await fetchCommentsFromAPI()
        await Comment.sync(with: serverComments, orm: orm)
    }
    
    // MARK: - Batch Processing
    
    /// Handle large datasets efficiently
    public static func batchSync() async {
        let orm = createFileORM(filename: "app.sqlite")
        
        let allUsers = await fetchAllUsersFromAPI() // Large dataset
        
        // Process in batches
        let batchSize = 100
        for batch in allUsers.chunked(into: batchSize) {
            let result = await User.sync(
                with: batch,
                orm: orm,
                changeCallback: { changes in
                    print("Batch processed: \(changes.totalChanges) changes")
                }
            )
        }
    }
    
    // MARK: - File-Based Sync
    
    /// Sync from JSON files (no API needed)
    public static func fileBasedSync() async {
        let orm = createFileORM(filename: "app.sqlite")
        
        // Load data from JSON file
        if let fileURL = Bundle.main.url(forResource: "users", withExtension: "json"),
           let data = try? Data(contentsOf: fileURL),
           let users = try? JSONDecoder().decode([User].self, from: data) {
            
            // Sync file data with database
            let result = await User.sync(with: users, orm: orm)
            print("Synced from file: \(try! result.get().totalChanges) users")
        }
    }
    
    // MARK: - Manual Data Sync
    
    /// Sync with manually created data
    public static func manualDataSync() async {
        let orm = createFileORM(filename: "app.sqlite")
        
        // Manually create data (admin panel, CSV import, etc.)
        let manualProducts = [
            Product(id: 1, name: "Special Edition iPhone", price: 1299.0, category: "Electronics"),
            Product(id: 2, name: "Limited MacBook", price: 2499.0, category: "Computers")
        ]
        
        // Sync manual data
        await Product.sync(with: manualProducts, orm: orm)
    }
}

// MARK: - Additional Model Examples

@ORMTable
struct Article: ORMTable {
    typealias IDType = Int
    var id: Int = 0
    var title: String = ""
    var content: String = ""
    var publishDate: Date = Date()
    
    // Required sync properties
    var lastSyncTimestamp: Date? = nil
    var isDirty: Bool = false
    var syncStatus: SyncStatus = .synced
    var serverID: String? = nil
    
    init() {}
}

@ORMTable
struct Category: ORMTable {
    typealias IDType = Int
    var id: Int = 0
    var name: String = ""
    var description: String = ""
    
    // Required sync properties
    var lastSyncTimestamp: Date? = nil
    var isDirty: Bool = false
    var syncStatus: SyncStatus = .synced
    var serverID: String? = nil
    
    init() {}
}

@ORMTable
struct Post: ORMTable {
    typealias IDType = Int
    var id: Int = 0
    var title: String = ""
    var content: String = ""
    var authorId: Int = 0
    var postDate: Date = Date()
    
    // Required sync properties
    var lastSyncTimestamp: Date? = nil
    var isDirty: Bool = false
    var syncStatus: SyncStatus = .synced
    var serverID: String? = nil
    
    init() {}
}

@ORMTable
struct Comment: ORMTable {
    typealias IDType = Int
    var id: Int = 0
    var content: String = ""
    var postId: Int = 0
    var authorId: Int = 0
    var commentDate: Date = Date()
    
    // Required sync properties
    var lastSyncTimestamp: Date? = nil
    var isDirty: Bool = false
    var syncStatus: SyncStatus = .synced
    var serverID: String? = nil
    
    init() {}
}

// MARK: - Mock API Functions

private func fetchOrdersFromAPI() async -> [SimpleSyncExamples.Order] {
    return [
        SimpleSyncExamples.Order(id: 1, customerId: 1, total: 99.99),
        SimpleSyncExamples.Order(id: 2, customerId: 2, total: 149.99)
    ]
}

private func uploadOrdersToAPI(_ orders: [SimpleSyncExamples.Order]) async -> [SimpleSyncExamples.Order] {
    return orders.map { order in
        var updated = order
        updated.serverID = "server_order_\(order.id)"
        return updated
    }
}

private func fetchProductsFromAPI() async -> [SimpleSyncExamples.Product] {
    return [
        SimpleSyncExamples.Product(id: 1, name: "iPhone", price: 999.0, category: "Electronics"),
        SimpleSyncExamples.Product(id: 2, name: "MacBook", price: 1999.0, category: "Computers")
    ]
}

private func fetchUsersFromAPI() async -> [SimpleSyncExamples.User] {
    return [
        SimpleSyncExamples.User(id: 1, username: "john", email: "john@example.com"),
        SimpleSyncExamples.User(id: 2, username: "jane", email: "jane@example.com")
    ]
}

private func fetchArticlesFromCMS() async -> [Article] {
    return [Article()]
}

private func fetchCategoriesFromCMS() async -> [Category] {
    return [Category()]
}

private func fetchPostsFromAPI() async -> [Post] {
    return [Post()]
}

private func fetchCommentsFromAPI() async -> [Comment] {
    return [Comment()]
}

private func fetchAllUsersFromAPI() async -> [SimpleSyncExamples.User] {
    return (1...1000).map { i in
        SimpleSyncExamples.User(id: i, username: "user\(i)", email: "user\(i)@example.com")
    }
}

// MARK: - Helper Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}