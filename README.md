# SwiftSync

A modern, type-safe SQLite ORM for Swift with zero external dependencies.

> **Note**: This is a prerelease version with a clean, modern API. All legacy compatibility has been removed in favor of the new ORM-prefixed naming convention.

## Features

- 🔒 **Type-safe** SQL queries with compile-time validation
- 🎭 **Actor-based** concurrency for thread-safe database operations
- 🎯 **Result types** for comprehensive error handling (no try/catch)
- 🏗️ **Swift macros** for automatic boilerplate generation
- 📦 **Zero dependencies** - uses only built-in SQLite3
- 🔄 **Migration system** with version tracking
- 📅 **Advanced date handling** with multiple format support
- 🔗 **Combine integration** for reactive data subscriptions
- 🔄 **Built-in sync** - comprehensive data synchronization with soft-sync, conflict resolution, and multi-model coordination
- 🚀 **Easy to use** - just conform to `ORMTable` protocol and use `@ORMTable` macro
- 🎨 **Clean API** - modern ORM-prefixed naming convention
- ⚡ **Protocol conformances** - automatic `Identifiable`, `Hashable`, and `Codable` support with generic property-based implementations
- 🌐 **Advanced Sync Features** - individual model sync, multi-model coordination, and KeyPath-based container extraction

## Installation

Add SwiftSync to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/jomaw0/SwiftSync.git", from: "1.0.0")
]
```

## What's New

This prerelease version features a completely modernized API:

- **ORM-Prefixed Types**: All types now use the `ORM` prefix (`ORMTable`, `ORMIndex`, `ORMQueryBuilder`, etc.)
- **ORM-Prefixed Macros**: All macros now use the `ORM` prefix (`@ORMTable`, `@ORMColumn`, `@ORMIndexed`, etc.) 
- **Clean Initialization**: Simple, modern initialization methods with sensible defaults
- **No Legacy Code**: All backward compatibility has been removed for a cleaner, more maintainable codebase
- **Better Defaults**: Default database is now `app.sqlite` for better naming conventions

## Quick Start

### Define a Table

```swift
import SwiftSync

@ORMTable
struct User: ORMTable {
    typealias IDType = Int
    
    var id: Int = 0
    var username: String
    var email: String
    var createdAt: Date
    var isActive: Bool = true
}
```

### Database Initialization

SwiftSync provides multiple ways to initialize your database:

```swift
// 1. Default database in Documents directory (creates app.sqlite)
let orm = ORM()

// 2. Named database with automatic .sqlite extension
let orm = ORM(.relative("myapp"))

// 3. In-memory database for testing
let orm = ORM(.memory)

// 4. Convenience functions
let orm = createFileORM(filename: "myapp") // Creates myapp.sqlite in Documents
let orm = createInMemoryORM() // For testing

await orm.open()
```

### Basic CRUD Operations

```swift

// Get repository
let userRepo = await orm.repository(for: User.self)

// Create table
await userRepo.createTable()

// Insert
var user = User(username: "john", email: "john@example.com", createdAt: Date())
let insertResult = await userRepo.insert(&user)
if case .failure(let error) = insertResult {
    print("Insert failed with error: \(error)")
    return
}

// Find by ID
let findResult = await userRepo.find(id: user.id)
switch findResult {
case .success(let foundUser):
    print("Found user: \(foundUser?.username ?? "Not found")")
case .failure(let error):
    print("Error: \(error)")
}

// Query with conditions
let query = ORMQueryBuilder<User>()
    .where("isActive", .equal, true)
    .orderBy("createdAt", ascending: false)
    .limit(10)

let activeUsers = await userRepo.findAll(query: query)
```

### Convenient Table Creation

SwiftSync provides several convenient ways to create multiple tables:

```swift
// 1. Variadic method for multiple tables
await orm.createTables(User.self, Post.self, Comment.self)

// 2. Open database and create tables in one step
await orm.openAndCreateTables(User.self, Post.self, Comment.self)

// 3. One-liner for in-memory database with tables
let orm = await createInMemoryORMWithTables(User.self, Post.self)

// 4. One-liner for file database with tables
let orm = await createFileORMWithTables("myapp", User.self, Post.self, Comment.self)

// All methods return ORMResult for proper error handling
switch await orm.openAndCreateTables(User.self, Post.self) {
case .success():
    print("Database ready!")
case .failure(let error):
    print("Setup failed: \(error)")
}
```

### Automatic Protocol Conformances

All `ORMTable` models automatically conform to `Identifiable`, `Hashable`, and `Codable` with generic implementations:

```swift
@ORMTable
struct User: ORMTable {
    var id: Int = 0
    var username: String
    var email: String
    var isActive: Bool = true
    
    // Automatically gets:
    // - Identifiable (uses 'id' property)
    // - Hashable (hashes ALL properties generically)
    // - Codable (for JSON/database serialization)
    // - Equatable (compares ALL properties generically)
}

// Use in Sets and as Dictionary keys
let users: Set<User> = [user1, user2, user3]
let userLookup: [User: String] = [user1: "admin", user2: "guest"]

// Equality and hashing based on ALL properties
let user1 = User(id: 1, username: "john", email: "john@example.com")
let user2 = User(id: 1, username: "johnny", email: "john@example.com") // Different username

user1 == user2  // false - different username even though same ID
user1.hashValue == user2.hashValue  // false - different hash

// Generic implementation uses Codable encoding for robust comparison
// Automatically handles all property types: String, Int, Date, Bool, etc.
```

### Data Synchronization

SwiftSync provides two powerful synchronization approaches to handle different real-world scenarios:

#### 🔄 **Sync vs SoftSync - When to Use Each**

**Traditional Sync** (exact mirror):
- **What it does**: Makes local database an exact mirror of server data
- **Behavior**: Inserts new items, updates existing items, **deletes items missing from server**
- **Use cases**: Product catalogs, system configurations, authoritative server data
- **Example**: E-commerce app syncing product catalog where discontinued products should be removed

**SoftSync** (preserve local data):
- **What it does**: Updates local database but **preserves local-only data**
- **Behavior**: Inserts new items, updates existing items, **never deletes anything**
- **Use cases**: User-generated content, drafts, offline-first apps, collaborative data
- **Example**: Note-taking app where users create local notes that shouldn't be deleted during server sync

#### 🌍 **Quick Usage Examples**

##### E-Commerce App
```swift
// Product catalog: Use traditional sync (exact mirror)
// Discontinued products should be removed from local database
let catalogResult = await Product.sync(with: serverProducts, orm: orm)

// User's shopping cart: Use softSync (preserve local items)
// Don't delete items user added while offline
let cartResult = await CartItem.softSync(with: serverCartItems, orm: orm)
```

##### Note-Taking App
```swift
// Shared notes: Use softSync (preserve user's local drafts)
// User might have unsaved local notes that shouldn't be deleted
let notesResult = await Note.softSync(with: serverNotes, orm: orm)

// App settings: Use traditional sync (exact mirror of server config)
let settingsResult = await AppSetting.sync(with: serverSettings, orm: orm)
```

#### 📊 **Multi-Model SoftSync - The Game Changer**

Real-world APIs often return complex responses with multiple data types. Instead of handling each model type separately, SwiftSync's multi-model softSync lets you coordinate everything in a single, elegant call.

##### The Problem: Complex API Responses
```swift
// Typical API response from a mobile app backend
struct AppDataResponse: Codable {
    let user: UserProfile
    let settings: [UserSetting]
    let posts: [Post] 
    let notifications: [Notification]
    let friends: [Friend]
    let categories: [Category]
    let products: [Product]
    let conversations: [Conversation]
    let achievements: [Achievement]
    let metadata: ResponseMetadata
}
```

##### Traditional Approach (Tedious & Error-Prone)
```swift
// Manual handling of each model type - lots of boilerplate!
let response = await fetchAppData()

let userResult = await UserProfile.softSync(with: [response.user], orm: orm)
let settingsResult = await UserSetting.softSync(with: response.settings, orm: orm)
let postsResult = await Post.softSync(with: response.posts, orm: orm)
let notificationsResult = await Notification.softSync(with: response.notifications, orm: orm)
let friendsResult = await Friend.softSync(with: response.friends, orm: orm)
let categoriesResult = await Category.sync(with: response.categories, orm: orm)
let productsResult = await Product.sync(with: response.products, orm: orm)
let conversationsResult = await Conversation.softSync(with: response.conversations, orm: orm)
let achievementsResult = await Achievement.softSync(with: response.achievements, orm: orm)

// Handle individual errors for each model type... 😫
```

##### ✨ SwiftSync Multi-Model Approach (Clean & Powerful)
```swift
// Handle everything in one elegant call!
let result = await orm.softSync(
    from: response,
    modelTypes: [
        UserProfile.self,
        UserSetting.self, 
        Post.self,
        Notification.self,
        Friend.self,
        Category.self,
        Product.self,
        Conversation.self,
        Achievement.self
    ],
    conflictResolution: .serverWins
)

// Single result handling with detailed breakdown
switch result {
case .success(let syncResults):
    // Get overview
    let totalChanges = syncResults.modelResults.values.map(\.totalChanges).reduce(0, +)
    print("✅ Sync completed: \(totalChanges) total changes across \(syncResults.modelResults.count) model types")
    
    // Detailed breakdown for each model type
    for (modelType, modelResult) in syncResults.modelResults {
        if modelResult.totalChanges > 0 {
            print("📊 \(modelType):")
            print("   • Inserted: \(modelResult.insertedCount)")
            print("   • Updated: \(modelResult.updatedCount)")
            print("   • Conflicts: \(modelResult.conflictsCount)")
        }
    }
    
case .failure(let error):
    print("❌ Sync failed: \(error)")
}
```

##### Advanced Multi-Model Usage Patterns

###### Pattern 1: Selective Model Sync
```swift
// Sync only user-related data on login
let loginResult = await orm.softSync(
    from: response,
    modelTypes: [UserProfile.self, UserSetting.self, Friend.self],
    conflictResolution: .localWins  // Keep user's local preferences
)

// Sync content data separately with different strategy
let contentResult = await orm.softSync(
    from: response,
    modelTypes: [Post.self, Category.self, Product.self],
    conflictResolution: .serverWins  // Server content is authoritative
)
```

###### Pattern 2: Conditional Multi-Model Sync
```swift
// Smart sync based on app state
func syncAppData(_ response: AppDataResponse) async {
    if isFirstTimeUser {
        // New user: sync everything with server priority
        await orm.softSync(
            from: response,
            modelTypes: [UserProfile.self, UserSetting.self, Post.self, Category.self],
            conflictResolution: .serverWins
        )
    } else {
        // Existing user: preserve local changes
        await orm.softSync(
            from: response,
            modelTypes: [UserProfile.self, UserSetting.self, Post.self],
            conflictResolution: .localWins
        )
    }
}
```

###### Pattern 3: Incremental Multi-Model Sync
```swift
// Large dataset: sync in chunks by model priority
class SmartSyncManager {
    func performIncrementalSync(_ response: AppDataResponse) async {
        // Phase 1: Critical user data first
        let criticalResult = await orm.softSync(
            from: response,
            modelTypes: [UserProfile.self, UserSetting.self],
            conflictResolution: .serverWins
        )
        
        // Phase 2: Social data
        let socialResult = await orm.softSync(
            from: response,
            modelTypes: [Friend.self, Conversation.self, Notification.self],
            conflictResolution: .localWins
        )
        
        // Phase 3: Content data (can be done in background)
        Task.detached {
            await orm.softSync(
                from: response,
                modelTypes: [Post.self, Category.self, Product.self],
                conflictResolution: .serverWins
            )
        }
    }
}
```

##### Key Benefits of Multi-Model SoftSync

1. **🚀 Simplified Code**: One call instead of multiple individual sync operations
2. **🔒 Atomic Operations**: All models sync together or none do (transaction safety)
3. **📊 Unified Results**: Single result object with breakdown for each model type
4. **⚡ Performance**: Optimized database operations and reduced overhead
5. **🛡️ Error Handling**: Centralized error handling instead of managing multiple failure points
6. **🎯 Flexible Strategies**: Different conflict resolution per sync operation
7. **📱 Type Safety**: Compile-time verification of model types and relationships

#### 🛠 **Advanced Sync Scenarios**

##### Selective Model Sync
```swift
// Real scenario: Social media app with different sync needs
struct SocialFeedResponse: Codable {
    let posts: [Post]
    let stories: [Story]
    let messages: [Message]
    let notifications: [Notification]
    let settings: [UserSetting]
}

let feedResponse = await fetchSocialFeed()

// Option 1: Sync everything with same strategy
let allResult = await orm.softSync(
    from: feedResponse,
    modelTypes: [Post.self, Story.self, Message.self, Notification.self, UserSetting.self],
    conflictResolution: .serverWins
)

// Option 2: Selective sync based on app state
if userIsOnline {
    // Sync user-generated content with soft-sync (preserve drafts)
    let contentResult = await orm.softSync(
        from: feedResponse,
        modelTypes: [Post.self, Message.self],
        conflictResolution: .localWins  // Keep user's changes
    )
    
    // Sync system data with exact mirror
    let systemResult = await UserSetting.sync(with: feedResponse.settings, orm: orm)
}
```

##### KeyPath-Based Extraction
```swift
// When you need fine-grained control over individual model types
struct ComplexAPIResponse: Codable {
    let userData: UserData
    let appData: AppData
    
    struct UserData: Codable {
        let profile: UserProfile
        let preferences: [UserPreference]
        let activities: [UserActivity]
    }
    
    struct AppData: Codable {
        let products: [Product]
        let categories: [Category]
        let promotions: [Promotion]
    }
}

let response = await fetchComplexData()

// Extract and sync user preferences with local priority
let prefResult = await UserPreference.softSync(
    from: response, 
    keyPath: \.userData.preferences, 
    orm: orm,
    conflictResolution: .localWins  // User's local preferences win
)

// Extract and sync products with server priority  
let productResult = await Product.sync(
    from: response,
    keyPath: \.appData.products,
    orm: orm,
    conflictResolution: .serverWins  // Server catalog is authoritative
)

// Handle special business logic for promotions
let promotionResult = await Promotion.softSync(
    from: response,
    keyPath: \.appData.promotions,
    orm: orm,
    conflictResolution: .custom { local, server in
        let localPromo = local as! Promotion
        let serverPromo = server as! Promotion
        
        // Custom logic: Keep higher discount value
        return localPromo.discountPercent > serverPromo.discountPercent ? localPromo : serverPromo
    }
)
```

#### ⚔️ **Conflict Resolution Strategies**

When the same item exists both locally and on the server, SwiftSync provides flexible conflict resolution:

```swift
// Available conflict resolution strategies
enum ConflictResolution {
    case serverWins    // Default: server data overwrites local
    case localWins     // Local data preserved in conflicts
    case newestWins    // Compare timestamps to determine winner
    case custom((local: any ORMTable, server: any ORMTable) async -> any ORMTable)
}
```

##### Real-World Conflict Resolution Examples

```swift
// 📝 Collaborative Document Editing
let result = await Document.softSync(
    with: serverDocuments,
    orm: orm,
    conflictResolution: .custom { local, server in
        let localDoc = local as! Document
        let serverDoc = server as! Document
        
        // Business logic: Merge document versions
        if localDoc.lastModified > serverDoc.lastModified {
            // Local is newer, but keep server's published status
            return Document(
                id: localDoc.id,
                title: localDoc.title,
                content: localDoc.content,
                lastModified: localDoc.lastModified,
                isPublished: serverDoc.isPublished  // Server decides publication
            )
        } else {
            return serverDoc  // Server version is newer
        }
    }
)

// 💰 Financial Data (Always use server)
let accountResult = await Account.softSync(
    with: serverAccounts,
    orm: orm,
    conflictResolution: .serverWins  // Financial data must be authoritative
)

// 👤 User Preferences (Keep local changes)
let prefsResult = await UserPreference.softSync(
    with: serverPreferences,
    orm: orm,
    conflictResolution: .localWins  // User's local settings take priority
)

// 📊 Analytics Data (Newest wins)
let analyticsResult = await AnalyticsEvent.softSync(
    with: serverEvents,
    orm: orm,
    conflictResolution: .newestWins  // Most recent data is most accurate
)

// 🛒 Shopping Cart (Smart merge)
let cartResult = await CartItem.softSync(
    with: serverCartItems,
    orm: orm,
    conflictResolution: .custom { local, server in
        let localItem = local as! CartItem
        let serverItem = server as! CartItem
        
        // Business logic: Use higher quantity, latest price
        return CartItem(
            id: localItem.id,
            productId: localItem.productId,
            quantity: max(localItem.quantity, serverItem.quantity),  // Higher quantity
            price: serverItem.price,  // Always use server price
            addedAt: localItem.addedAt  // Keep original add time
        )
    }
)
```

#### 🎯 **Best Practices & Guidelines**

##### When to Use Traditional Sync
- ✅ **Product catalogs** - Remove discontinued items
- ✅ **System configurations** - Exact server state required
- ✅ **Financial data** - Must match server exactly
- ✅ **Reference data** - Countries, currencies, categories
- ✅ **User permissions** - Security requires server authority

##### When to Use SoftSync  
- ✅ **User-generated content** - Notes, drafts, comments
- ✅ **Offline-first apps** - Don't lose user's work
- ✅ **Collaborative data** - Preserve local changes
- ✅ **Cache-like data** - OK to have extra local items
- ✅ **Social features** - Posts, likes, follows (user might have unsent items)

##### Common Patterns
```swift
// 🏪 E-commerce: Mixed sync strategies
class ECommerceSync {
    func syncShopData() async {
        let response = await fetchShopData()
        
        // Authoritative server data (exact mirror)
        await Product.sync(with: response.products, orm: orm)
        await Category.sync(with: response.categories, orm: orm)
        await ShippingMethod.sync(with: response.shippingMethods, orm: orm)
        
        // User data (preserve local changes)
        await WishlistItem.softSync(with: response.wishlistItems, orm: orm)
        await CartItem.softSync(with: response.cartItems, orm: orm)
        await UserReview.softSync(with: response.reviews, orm: orm, conflictResolution: .localWins)
        
        // Or handle everything at once with multi-model sync
        let result = await orm.softSync(
            from: response,
            modelTypes: [WishlistItem.self, CartItem.self, UserReview.self],
            conflictResolution: .localWins
        )
    }
}

// 📱 Social Media: Smart conflict resolution
class SocialMediaSync {
    func syncFeedData() async {
        let response = await fetchFeedData()
        
        await Post.softSync(
            with: response.posts,
            orm: orm,
            conflictResolution: .custom { local, server in
                let localPost = local as! Post
                let serverPost = server as! Post
                
                // Keep local draft status, use server for published posts
                if localPost.isDraft {
                    return localPost  // Don't overwrite user's drafts
                } else {
                    return serverPost  // Use server version for published posts
                }
            }
        )
    }
}
```

## Advanced Features

### Custom Column Names

```swift
@ORMTable
@ORMTableName("app_users")
struct User: ORMTable {
    var id: Int = 0
    
    @ORMColumn("user_name")
    var username: String
    
    @ORMColumn("email_address")
    var email: String
}
```

### Indexes and Constraints

```swift
@ORMTable
struct User: ORMTable {
    var id: Int = 0
    
    @ORMUnique
    var username: String
    
    @ORMIndexed
    var email: String
    
    @ORMIndexed
    var createdAt: Date
}
```

### Transactions

```swift
let result = await orm.transaction {
    var user1 = User(username: "alice", email: "alice@example.com", createdAt: Date())
    let insert1 = await userRepo.insert(&user1)
    
    guard case .success = insert1 else {
        return insert1.map { _ in () }
    }
    
    var user2 = User(username: "bob", email: "bob@example.com", createdAt: Date())
    return await userRepo.insert(&user2).map { _ in () }
}
```

### Migrations

```swift
class AddUserPreferences: BaseMigration {
    override func up(database: SQLiteDatabase) async -> ORMResult<Void> {
        database.execute("""
            CREATE TABLE user_preferences (
                user_id INTEGER PRIMARY KEY,
                theme TEXT DEFAULT 'light',
                notifications_enabled INTEGER DEFAULT 1
            )
        """).map { _ in () }
    }
    
    override func down(database: SQLiteDatabase) async -> ORMResult<Void> {
        database.execute("DROP TABLE user_preferences").map { _ in () }
    }
}

// Run migrations
let migrations = [AddUserPreferences()]
await orm.migrations.migrate(migrations)
```

### Query Builder

SwiftSync supports two query syntaxes - a fluent predicate-based syntax and the traditional builder pattern:

#### Predicate-Based Queries (Recommended)

```swift
// Complex queries with full type safety
let query = await orm.query(User.self)
    .where(.and([
        .column("age", .greaterThan, .integer(18)),
        .or([
            .column("name", .like, .text("%John%")),
            .isNotNull("email")
        ])
    ]))
    .orderBy("created_at", .descending)
    .limit(50)

let users = await query.fetch()

// Query directly from model type
let activeUsers = await User.query(using: orm)
    .where(.column("isActive", .equal, .bool(true)))
    .orderBy("username", .ascending)
    .fetch()

// Shorthand where on model
let adults = await User.where(.column("age", .greaterThanOrEqual, .integer(18)), using: orm)
    .fetch()

// Other predicates
let query = await orm.query(User.self)
    .where(.in("status", [.text("active"), .text("pending")]))
    .where(.between("score", .real(80.0), .real(100.0)))
    .where(.not(.isNull("email")))
```

#### Traditional Query Builder

```swift
let query = ORMQueryBuilder<User>()
    .where("createdAt", .greaterThan, Date().addingTimeInterval(-86400))
    .whereIn("status", ["active", "pending"])
    .orderBy("username")
    .limit(50)
    .offset(100)

// Joins
let query = ORMQueryBuilder<User>()
    .select("users.*", "COUNT(posts.id) as post_count")
    .leftJoin("posts", on: "posts.user_id = users.id")
    .groupBy("users.id")
    .having("post_count", .greaterThan, 5)
```

## Error Handling

All operations return `ORMResult<T>` (alias for `Result<T, ORMError>`):

```swift
let result = await userRepo.find(id: 1)

switch result {
case .success(let user):
    if let user = user {
        print("Found: \(user.username)")
    } else {
        print("User not found")
    }
case .failure(let error):
    print("Database error: \(error)")
}

// Or use convenient methods
let user = result.toOptional() // Logs error and returns optional
```

## Built-in Data Synchronization

SwiftSync includes comprehensive data synchronization capabilities. Every ORMTable model is automatically syncable with minimal setup and powerful conflict resolution.

### Simple Sync (Minimal API)

Every model automatically gets sync capabilities - just call `.sync(with:orm:)`:

```swift
// You have server data from your API
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
```

### Automatic Sync Properties

All ORMTable models automatically include sync metadata:

```swift
@ORMTable
struct User: ORMTable {
    var id: Int = 0
    var username: String = ""
    var email: String = ""
    
    // Sync properties are automatically included:
    var lastSyncTimestamp: Date? = nil
    var isDirty: Bool = false
    var syncStatus: SyncStatus = .synced
    var serverID: String? = nil
}
```

### Conflict Resolution

Multiple strategies for handling data conflicts:

```swift
// Server wins (default)
await User.sync(with: serverUsers, orm: orm)

// Local wins
await User.sync(with: serverUsers, orm: orm, conflictResolution: .localWins)

// Newest modification wins
await User.sync(with: serverUsers, orm: orm, conflictResolution: .newestWins)

// Custom resolution logic
await User.sync(
    with: serverUsers,
    orm: orm,
    conflictResolution: .custom { local, server in
        // Your custom logic here
        return local.email.contains("@company.com") ? local : server
    }
)
```

### Change Tracking

Monitor what changes during sync operations:

```swift
let result = await Product.sync(
    with: serverProducts,
    orm: orm,
    changeCallback: { changes in
        print("📊 Sync results:")
        print("➕ New products: \(changes.inserted.count)")
        print("📝 Updated products: \(changes.updated.count)")
        print("⚠️ Conflicts resolved: \(changes.conflicts)")
        
        // Log individual changes
        for product in changes.inserted {
            print("   New: \(product.name) - $\(product.price)")
        }
    }
)
```

### Two-Way Sync Pattern

Complete bidirectional synchronization:

```swift
// === DOWNLOAD PHASE ===
// 1. Get server data (your API call)
let serverOrders = await fetchOrdersFromAPI()

// 2. Sync with local - server wins for existing orders
await Order.sync(
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

if case .success(let orders) = localChanges, !orders.isEmpty {
    // 4. Upload to server (your API call)
    let uploadedOrders = await uploadOrdersToAPI(orders)
    
    // 5. Mark as synced
    await Order.markAsSynced(uploadedOrders, orm: orm)
    print("📤 Uploaded: \(uploadedOrders.count) orders")
}
```

### Real-World Use Cases

#### E-commerce App
```swift
// Products: server is authoritative
let serverProducts = await fetchProductsFromAPI()
await Product.sync(with: serverProducts, orm: orm) // Server wins by default

// Users: bidirectional with newest wins
let serverUsers = await fetchUsersFromAPI()
await User.sync(with: serverUsers, orm: orm, conflictResolution: .newestWins)

// Orders: upload local changes
let localOrders = await Order.getLocalChanges(orm: orm)
if case .success(let orders) = localOrders, !orders.isEmpty {
    let uploaded = await uploadOrdersToAPI(orders)
    await Order.markAsSynced(uploaded, orm: orm)
}
```

#### Content Management App
```swift
// Articles from CMS - server always wins
let articles = await fetchArticlesFromCMS()
await Article.sync(with: articles, orm: orm) // Default: server wins

// Categories from CMS
let categories = await fetchCategoriesFromCMS()
await Category.sync(with: categories, orm: orm)
```

#### File-Based Sync (No API Required)
```swift
// Load data from JSON file
if let fileURL = Bundle.main.url(forResource: "users", withExtension: "json"),
   let data = try? Data(contentsOf: fileURL),
   let users = try? JSONDecoder().decode([User].self, from: data) {
    
    // Sync file data with database
    let result = await User.sync(with: users, orm: orm)
    print("Synced from file: \(try! result.get().totalChanges) users")
}
```

### Key Features

- **Zero Setup**: Every ORMTable is automatically syncable
- **Minimal API**: One method call for basic sync operations
- **Flexible Conflicts**: Multiple resolution strategies with custom logic support
- **Change Tracking**: Detailed callbacks for monitoring sync operations
- **API Independent**: Works with any data source (REST, GraphQL, files, etc.)
- **Batch Processing**: Efficient handling of large datasets
- **Two-Way Sync**: Upload local changes and download server updates
- **Type Safe**: Full Swift type safety with Result-based error handling

## Combine Integration (iOS 16.0+)

SwiftSync provides reactive data subscriptions using Combine, perfect for SwiftUI and reactive programming patterns.

### Basic Subscriptions

```swift
import Combine
import SwiftUI

// Subscribe to all users
let allUsersSubscription = await userRepo.subscribe()

// Subscribe with a query filter
let activeUsersSubscription = await userRepo.subscribe(
    query: ORMQueryBuilder<User>().where("isActive", .equal, true)
)

// Subscribe to a single user by ID
let userSubscription = await userRepo.subscribe(id: 123)

// Subscribe to count of users
let countSubscription = await userRepo.subscribeCount()
```

### Fluent Query Subscriptions

```swift
// Method 1: Using ORMQueryBuilder with .subscribe(using:)
let subscription = ORMQueryBuilder<User>()
    .where("isActive", .equal, true)
    .where("score", .greaterThan, 100.0)
    .orderBy("username")
    .limit(50)
    .subscribe(using: userRepo)

// Method 2: Using repository.query() for fluent chaining
let subscription = await userRepo.query()
    .where("isActive", .equal, true)
    .whereLike("email", "%@company.com")
    .orderBy("createdAt", ascending: false)
    .limit(20)
    .subscribe()

// Subscribe to count with query
let countSubscription = await userRepo.query()
    .where("isActive", .equal, true)
    .subscribeCount()

// Subscribe to first result
let firstUserSubscription = await userRepo.query()
    .where("role", .equal, "admin")
    .orderBy("lastLogin", ascending: false)
    .subscribeFirst()

// Execute queries directly (non-reactive)
let users = await userRepo.query()
    .where("department", .equal, "Engineering")
    .findAll()

let count = await userRepo.query()
    .where("status", .equal, "pending")
    .count()
```

### Convenient Subscription Methods

SwiftSync provides many convenient subscription methods for common use cases:

```swift
// Existence subscriptions
let existsSubscription = await userRepo.subscribeExists() // Any users exist
let userExistsSubscription = await userRepo.subscribeExists(id: 123) // Specific user exists

// Latest/oldest subscriptions
let latestUserSubscription = await userRepo.subscribeLatest() // Most recently created
let oldestActiveUserSubscription = await userRepo.subscribeOldest(orderBy: "lastLogin")

// Filtered subscriptions
let activeUsersSubscription = await userRepo.subscribeWhere("isActive", equals: true)
let searchSubscription = await userRepo.subscribeWhere("username", contains: "john")

// Relationship subscriptions
let userPostsSubscription = await userRepo.subscribeRelated(Post.self, foreignKey: "userId", parentId: userId)
let postCountSubscription = await userRepo.subscribeRelatedCount(Post.self, foreignKey: "userId", parentId: userId)

// Chained convenience methods
let subscription = await userRepo.query()
    .whereActive(true)
    .belongsTo(organization)
    .newestFirst()
    .subscribeQuery()
```

### Date Query Convenience Methods

SwiftSync provides comprehensive date querying capabilities with intuitive, chainable methods:

#### Basic Date Comparisons

```swift
// Before/after specific dates
let users = await userRepo.query()
    .whereBefore("createdAt", date: Date())
    .findAll()

let recentPosts = await postRepo.query()
    .whereAfter("publishedAt", date: lastWeek)
    .newestFirst()
    .findAll()

// On or before/after (inclusive)
let subscription = await eventRepo.query()
    .whereOnOrAfter("eventDate", date: Date())
    .subscribeQuery()

// Specific date (ignoring time)
let todayEvents = await eventRepo.query()
    .whereOnDate("eventDate", date: Date())
    .findAll()
```

#### Relative Date Queries

```swift
// Today, yesterday, tomorrow
let todayPosts = await postRepo.query().whereToday().findAll()
let yesterdayEvents = await eventRepo.query().whereYesterday("eventDate").findAll()
let tomorrowTasks = await taskRepo.query().whereTomorrow("dueDate").subscribeQuery()

// This week, last week, next week
let thisWeekSubscription = await postRepo.query().whereThisWeek().subscribeQuery()
let lastWeekPosts = await postRepo.query().whereLastWeek().findAll()
let nextWeekEvents = await eventRepo.query().whereNextWeek("eventDate").findAll()

// Monthly queries
let thisMonthData = await dataRepo.query().whereThisMonth().findAll()
let lastMonthReports = await reportRepo.query().whereLastMonth("generatedAt").findAll()

// Yearly queries
let thisYearUsers = await userRepo.query().whereThisYear().findAll()
let lastYearMetrics = await metricRepo.query().whereLastYear("recordedAt").findAll()
```

#### Time-Based Queries

```swift
// Last N days/hours/minutes
let recentActivity = await activityRepo.query()
    .whereLastDays(7)
    .newestFirst()
    .findAll()

let hourlyMetrics = await metricRepo.query()
    .whereLastHours(24)
    .subscribeQuery()

let recentAlerts = await alertRepo.query()
    .whereLastMinutes(30)
    .subscribeQuery()

// Future queries
let upcomingEvents = await eventRepo.query()
    .whereNextDays(7)
    .orderBy("eventDate")
    .findAll()
```

#### Date Range Queries

```swift
// Within specific date ranges
let dateRange = await postRepo.query()
    .whereWithinDateRange("publishedAt", from: startDate, to: endDate)
    .findAll()

// Using the existing whereDateBetween method
let rangeQuery = await userRepo.query()
    .whereDateBetween("createdAt", from: startDate, to: endDate)
    .subscribeQuery()
```

#### Date Component Queries

```swift
// Specific year, month, or weekday
let posts2024 = await postRepo.query().whereYear("publishedAt", 2024).findAll()
let januaryEvents = await eventRepo.query().whereMonth("eventDate", 1).findAll()
let mondayTasks = await taskRepo.query().whereWeekday("dueDate", 2).findAll() // 2 = Monday

// Weekend vs weekday queries
let weekendActivity = await activityRepo.query().whereWeekend().subscribeQuery()
let weekdayReports = await reportRepo.query().whereWeekdays("createdAt").findAll()
```

#### Advanced Chained Date Queries

```swift
// Complex date filtering with subscriptions
let complexSubscription = await taskRepo.query()
    .whereThisMonth("createdAt")
    .whereAfter("dueDate", date: Date())
    .whereActive(true)
    .newestFirst("createdAt")
    .subscribeQuery()

// Multiple date conditions
let filtered = await eventRepo.query()
    .whereLastDays(30)
    .whereOnOrAfter("eventDate", date: Date())
    .whereWeekdays("eventDate")
    .findAll()

// Date queries with other filters
let activeUsersPastWeek = await userRepo.query()
    .whereLastWeek("lastLoginAt")
    .whereActive(true)
    .subscribeWhere("role", equals: "admin")
```

All date methods:
- Default to `"createdAt"` column but accept custom column names
- Work seamlessly with subscriptions and regular queries
- Support method chaining for complex filters
- Handle time zones automatically using the device's current calendar

### SwiftUI Integration

```swift
@available(iOS 16.0, *)
struct UserListView: View {
    @StateObject private var usersSubscription: SimpleQuerySubscription<User>
    @StateObject private var countSubscription: SimpleCountSubscription<User>
    
    private let userRepository: Repository<User>
    
    init(userRepository: Repository<User>) async {
        self.userRepository = userRepository
        self._usersSubscription = StateObject(wrappedValue: userRepository.subscribe())
        self._countSubscription = StateObject(wrappedValue: await userRepository.query()
            .where("isActive", .equal, true)
            .subscribeCount())
    }
    
    var body: some View {
        VStack {
            // Display count
            switch countSubscription.result {
            case .success(let count):
                Text("Total Users: \(count)")
            case .failure(let error):
                Text("Error: \(error)")
            }
            
            // Display users
            switch usersSubscription.result {
            case .success(let users):
                List(users, id: \.id) { user in
                    Text(user.username)
                }
            case .failure(let error):
                Text("Error: \(error)")
            }
            
            Button("Add User") {
                Task { await addRandomUser() }
            }
        }
    }
    
    private func addRandomUser() async {
        var user = User(username: "user\(Int.random(in: 1000...9999))", 
                       email: "test@example.com", 
                       createdAt: Date())
        _ = await userRepository.insert(&user)
        // UI automatically updates via subscription
    }
}
```

### Programmatic Usage

```swift
@available(iOS 16.0, *)
class UserManager: ObservableObject {
    @Published var users: [User] = []
    @Published var userCount: Int = 0
    
    private var cancellables = Set<AnyCancellable>()
    private let userRepository: Repository<User>
    
    init(userRepository: Repository<User>) async {
        self.userRepository = userRepository
        await setupSubscriptions()
    }
    
    @MainActor
    private func setupSubscriptions() async {
        // Subscribe to all users
        let usersSubscription = await userRepository.subscribe()
        usersSubscription.$result
            .compactMap { result -> [User]? in
                if case .success(let users) = result {
                    return users
                }
                return nil
            }
            .assign(to: \.users, on: self)
            .store(in: &cancellables)
        
        // Subscribe to count
        let countSubscription = await userRepository.subscribeCount()
        countSubscription.$result
            .compactMap { result -> Int? in
                if case .success(let count) = result {
                    return count
                }
                return nil
            }
            .assign(to: \.userCount, on: self)
            .store(in: &cancellables)
    }
}
```

### Key Features

- **Automatic Updates**: Subscriptions automatically emit new values when data changes
- **Type-Safe**: Full type safety with Result types for error handling
- **Thread-Safe**: Uses actors and MainActor for proper concurrency
- **Memory Efficient**: Proper cleanup and weak references
- **SwiftUI Ready**: ObservableObject pattern for seamless integration

## API Reference

### Core Types

- `ORMTable` - Protocol for database tables
- `ORMQueryBuilder<T>` - Type-safe query builder  
- `ORMResult<T>` - Result type alias for `Result<T, ORMError>`
- `ORMIndex` - Database index definition
- `ORMUniqueConstraint` - Unique constraint definition

### Macros

- `@ORMTable` - Generates boilerplate for table conformance
- `@ORMTableName("name")` - Custom table name
- `@ORMColumn("name")` - Custom column name
- `@ORMPrimaryKey` - Mark primary key property
- `@ORMIndexed` - Create database index
- `@ORMUnique` - Add unique constraint

### Initialization

- `ORM()` - Default database (app.sqlite in Documents)
- `ORM(.relative("name"))` - Named database file
- `ORM(.memory)` - In-memory database
- `createFileORM(filename:)` - Convenience function
- `createInMemoryORM()` - Convenience function

## Requirements

- Swift 6.1+
- iOS 16.0+ / macOS 13.0+ / tvOS 16.0+ / watchOS 9.0+
- Combine integration requires iOS 16.0+ / macOS 13.0+

## License

MIT License - see LICENSE file for details
