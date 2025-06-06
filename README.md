# SQLiteORM

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
- 🚀 **Easy to use** - just conform to `ORMTable` protocol and use `@ORMTable` macro
- 🎨 **Clean API** - modern ORM-prefixed naming convention

## Installation

Add SQLiteORM to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/jomaw0/SQLiteORM-swift.git", from: "1.0.0")
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
import SQLiteORM

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

SQLiteORM provides multiple ways to initialize your database:

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

SQLiteORM provides several convenient ways to create multiple tables:

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

## Combine Integration (iOS 16.0+)

SQLiteORM provides reactive data subscriptions using Combine, perfect for SwiftUI and reactive programming patterns.

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

SQLiteORM provides many convenient subscription methods for common use cases:

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

SQLiteORM provides comprehensive date querying capabilities with intuitive, chainable methods:

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
