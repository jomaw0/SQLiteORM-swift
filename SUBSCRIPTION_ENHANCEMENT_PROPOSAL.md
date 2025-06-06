# SQLiteORM Subscription System Enhancement Proposal

## Current State Analysis

### Why "Simple"?

The current subscription types are prefixed with "Simple" because they implement a **straightforward, race-condition-free approach** with minimal API surface:

- **`SimpleQuerySubscription<T>`** - Array of models with optional filtering
- **`SimpleSingleQuerySubscription<T>`** - Single model (by ID or first match)  
- **`SimpleCountSubscription<T>`** - Count queries

**Key Innovation: Atomic Setup Pattern**
```swift
private func atomicSetup() async {
    // 1. Subscribe to changes FIRST (before loading data)
    let publisher = await changeNotifier.publisher(for: T.tableName)
    cancellable = publisher.sink { [weak self] in
        Task { [weak self] in await self?.refreshData() }
    }
    
    // 2. THEN load initial data
    // Race condition eliminated: concurrent changes auto-trigger refresh
    await refreshData()
}
```

## Identified Limitations

### 1. **Table-Level Notifications Only**
- All changes to a table trigger ALL subscriptions for that table
- No row-level or filtered change notifications
- Inefficient for large tables with many subscriptions

### 2. **Limited Subscription Types**
- Only 3 built-in types with no extensibility
- No specialized patterns (pagination, grouping, aggregation)
- No relationship-aware subscriptions

### 3. **Performance Issues**
- No batch notification coalescing
- No subscription-level filtering before data refresh
- Potential UI thrashing with rapid changes

### 4. **Missing Advanced Features**
- No subscription composition
- No middleware/transformation pipeline
- No debugging/monitoring capabilities

## Enhancement Proposals

### Phase 1: Advanced Subscription Types

#### A. **Paginated Subscriptions** (for large datasets)
```swift
@MainActor
class PaginatedQuerySubscription<T: ORMTable>: ObservableObject {
    @Published var currentPage: [T] = []
    @Published var hasNextPage: Bool = false
    @Published var hasPreviousPage: Bool = false
    @Published var totalCount: Int = 0
    @Published var currentPageIndex: Int = 0
    
    private let pageSize: Int
    private let repository: Repository<T>
    private let query: ORMQueryBuilder<T>?
    
    init(repository: Repository<T>, query: ORMQueryBuilder<T>? = nil, pageSize: Int = 20) {
        self.repository = repository
        self.query = query
        self.pageSize = pageSize
        Task { await atomicSetup() }
    }
    
    func loadNextPage() async { /* implementation */ }
    func loadPreviousPage() async { /* implementation */ }
    func goToPage(_ index: Int) async { /* implementation */ }
}

// Usage:
let paginatedUsers = await userRepo.subscribePaginated(
    query: ORMQueryBuilder<User>().where("isActive", .equal, true),
    pageSize: 50
)
```

#### B. **Grouped Subscriptions** (for categorized data)
```swift
@MainActor
class GroupedQuerySubscription<T: ORMTable, GroupKey: Hashable>: ObservableObject {
    @Published var groups: [GroupKey: [T]] = [:]
    @Published var sortedGroupKeys: [GroupKey] = []
    
    private let groupBy: KeyPath<T, GroupKey>
    
    init(repository: Repository<T>, 
         query: ORMQueryBuilder<T>? = nil,
         groupBy: KeyPath<T, GroupKey>) {
        self.groupBy = groupBy
        Task { await atomicSetup() }
    }
}

// Usage:
let usersByDepartment = await userRepo.subscribeGrouped(
    query: ORMQueryBuilder<User>().where("isActive", .equal, true),
    groupBy: \.department
)
```

#### C. **Search Subscriptions** (with debouncing)
```swift
@MainActor
class SearchSubscription<T: ORMTable>: ObservableObject {
    @Published var searchText: String = "" {
        didSet { scheduleSearch() }
    }
    @Published var results: [T] = []
    @Published var isSearching: Bool = false
    @Published var hasNoResults: Bool = false
    
    private let searchFields: [String]
    private let debounceInterval: TimeInterval
    private var searchTask: Task<Void, Never>?
    
    init(repository: Repository<T>, 
         searchFields: [String],
         debounceInterval: TimeInterval = 0.3) {
        self.searchFields = searchFields
        self.debounceInterval = debounceInterval
    }
    
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }
}

// Usage:
let userSearch = SearchSubscription(
    repository: userRepo,
    searchFields: ["username", "email", "firstName", "lastName"],
    debounceInterval: 0.5
)
```

#### D. **Aggregation Subscriptions** (for computed values)
```swift
@MainActor
class AggregationSubscription<T: ORMTable>: ObservableObject {
    @Published var sum: Double = 0
    @Published var average: Double = 0
    @Published var min: Double = 0
    @Published var max: Double = 0
    @Published var count: Int = 0
    
    private let field: String
    
    init(repository: Repository<T>, 
         query: ORMQueryBuilder<T>? = nil,
         field: String) {
        self.field = field
        Task { await atomicSetup() }
    }
}

// Usage:
let salesStats = await orderRepo.subscribeAggregation(
    query: ORMQueryBuilder<Order>().where("status", .equal, "completed"),
    field: "total"
)
```

### Phase 2: Subscription Architecture Improvements

#### A. **Smart Change Notifications**
```swift
// Enhanced ChangeNotifier with row-level tracking
actor SmartChangeNotifier {
    private var tablePublishers: [String: PassthroughSubject<ChangeEvent, Never>] = [:]
    
    enum ChangeEvent {
        case inserted(tableName: String, id: Any)
        case updated(tableName: String, id: Any, changes: [String: Any])
        case deleted(tableName: String, id: Any)
        case bulkChange(tableName: String) // fallback for complex operations
    }
    
    // Subscriptions can filter based on specific row IDs or field changes
    func publisher(for tableName: String, 
                  filterBy: ChangeFilter? = nil) -> AnyPublisher<ChangeEvent, Never> {
        // Implementation with filtering logic
    }
}

enum ChangeFilter {
    case rowIds([Any])
    case affectsFields([String])
    case custom((ChangeEvent) -> Bool)
}
```

#### B. **Subscription Factory Pattern**
```swift
// Generic subscription factory for extensibility
protocol QuerySubscription: ObservableObject {
    associatedtype Model: ORMTable
    associatedtype Configuration
    
    init(repository: Repository<Model>, 
         query: ORMQueryBuilder<Model>?, 
         configuration: Configuration)
}

extension Repository {
    func subscribe<S: QuerySubscription>(
        _ subscriptionType: S.Type,
        query: ORMQueryBuilder<T>? = nil,
        configuration: S.Configuration
    ) async -> S where S.Model == T {
        return S(repository: self, query: query, configuration: configuration)
    }
}

// Usage:
let customSubscription = await userRepo.subscribe(
    MyCustomSubscription.self,
    query: someQuery,
    configuration: MyCustomSubscription.Configuration(...)
)
```

#### C. **Subscription Composition**
```swift
@MainActor
class CombinedSubscription: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    private var subscriptions: [any ObservableObject] = []
    
    init(@SubscriptionBuilder _ builder: () -> [any ObservableObject]) {
        self.subscriptions = builder()
        setupCombination()
    }
}

@resultBuilder
struct SubscriptionBuilder {
    static func buildBlock(_ subscriptions: (any ObservableObject)...) -> [any ObservableObject] {
        return Array(subscriptions)
    }
}

// Usage:
let dashboardData = CombinedSubscription {
    await userRepo.subscribe()
    await postRepo.subscribe(query: recentPostsQuery)
    await analyticsRepo.subscribeAggregation(field: "views")
}
.debounce(for: 0.3)
.distinctUntilChanged()
```

### Phase 3: Performance Optimizations

#### A. **Batch Notification Coalescing**
```swift
actor BatchingChangeNotifier {
    private var pendingChanges: [String: Set<ChangeEvent>] = [:]
    private var batchingTasks: [String: Task<Void, Never>] = [:]
    
    func notifyChange(_ event: ChangeEvent, batchWindow: TimeInterval = 0.1) {
        // Collect changes and emit batched notifications
    }
}
```

#### B. **Subscription-Level Filtering**
```swift
// Before refreshing data, check if changes are relevant
private func shouldRefreshForChange(_ event: ChangeEvent) -> Bool {
    switch event {
    case .updated(_, let id, let changes):
        // Only refresh if this subscription cares about the changed fields
        return query?.affectsFields(Array(changes.keys)) ?? true
    case .inserted, .deleted:
        // Always refresh for insertions/deletions that match our query
        return true
    }
}
```

#### C. **Memory-Efficient Subscriptions**
```swift
// Weak references and automatic cleanup
class SubscriptionManager {
    private var activeSubscriptions: [WeakSubscriptionWrapper] = []
    
    func register<T: ObservableObject>(_ subscription: T) {
        cleanup() // Remove deallocated subscriptions
        activeSubscriptions.append(WeakSubscriptionWrapper(subscription))
    }
    
    private func cleanup() {
        activeSubscriptions.removeAll { $0.subscription == nil }
    }
}
```

### Phase 4: Developer Experience Improvements

#### A. **SwiftUI Integration Enhancements**
```swift
// Simplified SwiftUI usage
struct UserListView: View {
    @StateObject private var users = Repository<User>.subscribe()
    @StateObject private var userCount = Repository<User>.subscribeCount()
    
    var body: some View {
        NavigationView {
            List(users.items, id: \.id) { user in
                UserRowView(user: user)
            }
            .navigationTitle("Users (\(userCount.value))")
            .refreshable {
                await users.refresh()
            }
        }
    }
}

// Property wrapper for easier subscription management
@propertyWrapper
struct Subscribe<T: ORMTable>: DynamicProperty {
    @StateObject private var subscription: SimpleQuerySubscription<T>
    
    init(repository: Repository<T>, query: ORMQueryBuilder<T>? = nil) {
        self._subscription = StateObject(wrappedValue: SimpleQuerySubscription(
            repository: repository,
            query: query
        ))
    }
    
    var wrappedValue: ORMResult<[T]> {
        subscription.result
    }
}
```

#### B. **Debugging and Monitoring**
```swift
// Subscription debugging tools
extension QuerySubscription {
    var debugInfo: SubscriptionDebugInfo {
        SubscriptionDebugInfo(
            type: String(describing: type(of: self)),
            tableName: Model.tableName,
            query: query?.debugDescription,
            lastRefresh: lastRefreshTime,
            refreshCount: refreshCount,
            memoryUsage: memoryFootprint
        )
    }
}

// Global subscription monitor
class SubscriptionMonitor {
    static let shared = SubscriptionMonitor()
    
    func getAllActiveSubscriptions() -> [SubscriptionDebugInfo] {
        // Return debug info for all active subscriptions
    }
    
    func subscriptionMetrics() -> SubscriptionMetrics {
        // Performance metrics, memory usage, etc.
    }
}
```

## Migration Strategy

### 1. **Preserve Existing API**
- Keep all current "Simple" subscription types
- Add new types alongside existing ones
- No breaking changes to current implementation

### 2. **Gradual Enhancement**
- Phase 1: Add new subscription types
- Phase 2: Enhance change notification system (opt-in)
- Phase 3: Performance optimizations (transparent)
- Phase 4: Developer experience improvements

### 3. **Configuration Options**
```swift
// Allow opting into enhanced features
let orm = ORM(path: "app.sqlite", subscriptionConfig: .enhanced)

enum SubscriptionConfig {
    case simple    // Current behavior
    case enhanced  // New features enabled
}
```

## Benefits of This Approach

1. **Backwards Compatibility**: No breaking changes to existing code
2. **Performance**: Row-level notifications and batching reduce unnecessary work
3. **Flexibility**: Plugin architecture allows custom subscription types
4. **Developer Experience**: Simplified APIs and better debugging tools
5. **Scalability**: Handles large datasets and complex queries efficiently

## Conclusion

The current "Simple" subscription system is solid but represents just the foundation. By building on the excellent atomic setup pattern and expanding with specialized subscription types, improved performance, and better developer tools, SQLiteORM can become a best-in-class reactive data layer for Swift applications.

The key is maintaining the simplicity and reliability of the current system while adding power features that developers can opt into as needed.

## Implementation Status

### Phase 0: Naming Convention Cleanup ✅ Complete
**Commit: c03b417** (feature/subscription-naming-refactor branch)

**What was implemented:**
- Created new `QuerySubscription` class to replace `SimpleQuerySubscription`
- Created new `SingleQuerySubscription` class to replace `SimpleSingleQuerySubscription`  
- Created new `CountSubscription` class to replace `SimpleCountSubscription`
- Updated `Repository` with new subscription methods maintaining backward compatibility:
  - `subscribeQuery()` -> Returns `QuerySubscription<T>`
  - `subscribeSingle(id:)` -> Returns `SingleQuerySubscription<T>`
  - `subscribeSingle(query:)` -> Returns `SingleQuerySubscription<T>`
  - `subscribeCountQuery()` -> Returns `CountSubscription<T>`
- Added deprecation warnings to existing `Simple*` classes
- Created comprehensive test suite `ModernSubscriptionTests.swift`
- All functionality preserved with cleaner, more professional naming
- Full backward compatibility maintained

**Next Steps:**
Ready to proceed with Phase 1 (Advanced Subscription Types) when needed.

**Fluent Query Builder Integration** ✅ Complete
**Commit: d314db1** (develop branch)

**Additional enhancements implemented:**
- Added new subscription methods to `QueryBuilderWithRepository` for fluent chaining
- Support for both direct repository subscriptions and query builder chaining:
  - `repo.subscribeQuery()` (direct)
  - `repo.query().where(...).subscribeQuery()` (fluent chaining)
- Updated example project to demonstrate modern subscription API
- Added comprehensive tests for all query builder subscription patterns
- All subscription functionality now available through fluent query builder interface
- Maintains full backward compatibility with clear deprecation guidance