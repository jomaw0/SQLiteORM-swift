# SQLiteORM

A modern, type-safe SQLite ORM for Swift with zero external dependencies.

## Features

- 🔒 **Type-safe** SQL queries with compile-time validation
- 🎭 **Actor-based** concurrency for thread-safe database operations
- 🎯 **Result types** for comprehensive error handling (no try/catch)
- 🏗️ **Swift macros** for automatic boilerplate generation
- 📦 **Zero dependencies** - uses only built-in SQLite3
- 🔄 **Migration system** with version tracking
- 📅 **Advanced date handling** with multiple format support
- 🚀 **Easy to use** - just conform to `Model` protocol

## Installation

Add SQLiteORM to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/SQLiteORM.git", from: "1.0.0")
]
```

## Quick Start

### Define a Model

```swift
import SQLiteORM

@Model
struct User: Model {
    typealias IDType = Int
    
    var id: Int = 0
    var username: String
    var email: String
    var createdAt: Date
    var isActive: Bool = true
}
```

### Basic Usage

```swift
// Initialize ORM
let orm = ORM(path: "database.sqlite")
await orm.open()

// Get repository
let userRepo = await orm.repository(for: User.self)

// Create table
await userRepo.createTable()

// Insert
var user = User(username: "john", email: "john@example.com", createdAt: Date())
let insertResult = await userRepo.insert(&user)

// Find by ID
let findResult = await userRepo.find(id: user.id)
switch findResult {
case .success(let foundUser):
    print("Found user: \(foundUser?.username ?? "Not found")")
case .failure(let error):
    print("Error: \(error)")
}

// Query with conditions
let query = QueryBuilder<User>()
    .where("isActive", .equal, true)
    .orderBy("createdAt", ascending: false)
    .limit(10)

let activeUsers = await userRepo.findAll(query: query)
```

## Advanced Features

### Custom Column Names

```swift
@Model
@Table("app_users")
struct User: Model {
    var id: Int = 0
    
    @Column("user_name")
    var username: String
    
    @Column("email_address")
    var email: String
}
```

### Indexes and Constraints

```swift
@Model
struct User: Model {
    var id: Int = 0
    
    @Unique
    var username: String
    
    @Indexed
    var email: String
    
    @Indexed
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

SQLiteORM supports two query syntaxes - a fluent predicate-based syntax and the traditional builder pattern:

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
// Still supported for compatibility
let query = QueryBuilder<User>()
    .where("createdAt", .greaterThan, Date().addingTimeInterval(-86400))
    .whereIn("status", ["active", "pending"])
    .orderBy("username")
    .limit(50)
    .offset(100)

// Joins
let query = QueryBuilder<User>()
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

## Requirements

- Swift 6.1+
- iOS 16.0+ / macOS 13.0+ / tvOS 16.0+ / watchOS 9.0+

## License

MIT License - see LICENSE file for details