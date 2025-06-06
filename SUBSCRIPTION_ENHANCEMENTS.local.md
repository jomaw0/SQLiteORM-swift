# SwiftSync Subscription System Enhancement Plan

## Executive Summary

The current "Simple" subscription system is excellent but represents only the foundation. This document outlines a comprehensive enhancement plan to create a modern, reliable, and robust reactive data framework while maintaining backward compatibility.

## Phase 0: Naming Rationalization

### Current Issue
The "Simple" prefix suggests limited functionality and doesn't reflect the sophisticated atomic setup pattern that eliminates race conditions.

### Proposed Solutions

#### Option A: Rename to "Basic" (Recommended)
```swift
// Current -> Proposed
SimpleQuerySubscription<T>       -> BasicQuerySubscription<T>
SimpleSingleQuerySubscription<T> -> BasicSingleQuerySubscription<T> 
SimpleCountSubscription<T>       -> BasicCountSubscription<T>
```

**Rationale:** "Basic" implies foundational/essential rather than limited. These are the core subscription types that most apps need.

#### Option B: Remove Prefix Entirely
```swift
// Current -> Proposed  
SimpleQuerySubscription<T>       -> QuerySubscription<T>
SimpleSingleQuerySubscription<T> -> SingleQuerySubscription<T>
SimpleCountSubscription<T>       -> CountSubscription<T>
```

**Rationale:** Clean, direct naming. These become the default subscription types.

#### Option C: Hybrid Approach (Most Flexible)
```swift
// Keep current names as typealiases for compatibility
public typealias SimpleQuerySubscription<T> = QuerySubscription<T>
public typealias SimpleSingleQuerySubscription<T> = SingleQuerySubscription<T>
public typealias SimpleCountSubscription<T> = CountSubscription<T>

// New primary names
public class QuerySubscription<T: ORMTable>: ObservableObject { }
public class SingleQuerySubscription<T: ORMTable>: ObservableObject { }
public class CountSubscription<T: ORMTable>: ObservableObject { }
```

**Benefits:**
- Zero breaking changes
- Clean primary API
- Gradual migration path
- Deprecation warnings guide users to new names

### Implementation Strategy
1. Create new classes with clean names
2. Keep existing classes as typealiases
3. Add deprecation warnings to old names
4. Update documentation to use new names
5. Eventual removal in major version

## Phase 1: Advanced Subscription Types

### 1. Paginated Subscriptions

**Use Case:** Large datasets (thousands of records) that need efficient loading and display.

**Detailed Implementation:**
```swift
@MainActor
public class PaginatedQuerySubscription<T: ORMTable>: ObservableObject {
    // Published properties for UI binding
    @Published public private(set) var currentPage: [T] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: ORMError?
    @Published public private(set) var hasNextPage: Bool = false
    @Published public private(set) var hasPreviousPage: Bool = false
    @Published public private(set) var currentPageIndex: Int = 0
    @Published public private(set) var totalCount: Int = 0
    @Published public private(set) var totalPages: Int = 0
    
    // Configuration
    public let pageSize: Int
    public let prefetchThreshold: Int // Load next page when within N items of end
    
    private let repository: Repository<T>
    private let baseQuery: ORMQueryBuilder<T>?
    private var changeNotifier: ChangeNotifier
    private var cancellable: AnyCancellable?
    
    // Cache for faster navigation
    private var pageCache: [Int: [T]] = [:]
    private let maxCachedPages: Int = 5
    
    public init(repository: Repository<T>, 
                query: ORMQueryBuilder<T>? = nil,
                pageSize: Int = 20,
                prefetchThreshold: Int = 5) {
        self.repository = repository
        self.baseQuery = query
        self.pageSize = pageSize
        self.prefetchThreshold = prefetchThreshold
        self.changeNotifier = repository.changeNotifier
        
        Task { await atomicSetup() }
    }
    
    private func atomicSetup() async {
        // Atomic setup pattern: subscribe BEFORE loading data
        let publisher = await changeNotifier.publisher(for: T.tableName)
        cancellable = publisher.sink { [weak self] in
            Task { [weak self] in
                await self?.handleDataChange()
            }
        }
        
        // Load initial page and count
        await loadInitialData()
    }
    
    private func loadInitialData() async {
        isLoading = true
        error = nil
        
        async let countResult = repository.count(query: baseQuery)
        async let pageResult = loadPage(0)
        
        let (count, page) = await (countResult, pageResult)
        
        switch (count, page) {
        case (.success(let totalCount), .success(let pageData)):
            self.totalCount = totalCount
            self.totalPages = (totalCount + pageSize - 1) / pageSize
            self.currentPage = pageData
            self.currentPageIndex = 0
            self.pageCache[0] = pageData
            self.hasNextPage = totalPages > 1
            self.hasPreviousPage = false
        case (.failure(let error), _), (_, .failure(let error)):
            self.error = error
        }
        
        isLoading = false
    }
    
    private func loadPage(_ pageIndex: Int) async -> ORMResult<[T]> {
        let offset = pageIndex * pageSize
        let query = (baseQuery ?? ORMQueryBuilder<T>())
            .limit(pageSize)
            .offset(offset)
        
        return await repository.findAll(query: query)
    }
    
    // Public API
    public func goToNextPage() async {
        guard hasNextPage else { return }
        await goToPage(currentPageIndex + 1)
    }
    
    public func goToPreviousPage() async {
        guard hasPreviousPage else { return }
        await goToPage(currentPageIndex - 1)
    }
    
    public func goToPage(_ pageIndex: Int) async {
        guard pageIndex >= 0 && pageIndex < totalPages else { return }
        
        isLoading = true
        error = nil
        
        // Check cache first
        if let cachedPage = pageCache[pageIndex] {
            currentPage = cachedPage
            updatePageState(pageIndex)
        } else {
            let result = await loadPage(pageIndex)
            
            switch result {
            case .success(let pageData):
                currentPage = pageData
                updatePageState(pageIndex)
                
                // Cache management
                pageCache[pageIndex] = pageData
                trimCache()
                
                // Prefetch adjacent pages
                await prefetchAdjacentPages(pageIndex)
                
            case .failure(let error):
                self.error = error
            }
        }
        
        isLoading = false
    }
    
    private func updatePageState(_ pageIndex: Int) {
        currentPageIndex = pageIndex
        hasNextPage = pageIndex < totalPages - 1
        hasPreviousPage = pageIndex > 0
    }
    
    private func trimCache() {
        guard pageCache.count > maxCachedPages else { return }
        
        let sortedKeys = pageCache.keys.sorted()
        let currentIndex = currentPageIndex
        
        // Keep current page and nearby pages
        let keysToKeep = sortedKeys.filter { abs($0 - currentIndex) <= 2 }
        let keysToRemove = Set(sortedKeys).subtracting(keysToKeep)
        
        for key in keysToRemove.prefix(pageCache.count - maxCachedPages) {
            pageCache.removeValue(forKey: key)
        }
    }
    
    private func prefetchAdjacentPages(_ currentPageIndex: Int) async {
        let pagesToPrefetch = [currentPageIndex - 1, currentPageIndex + 1]
            .filter { $0 >= 0 && $0 < totalPages && pageCache[$0] == nil }
        
        for pageIndex in pagesToPrefetch {
            Task {
                let result = await loadPage(pageIndex)
                if case .success(let pageData) = result {
                    pageCache[pageIndex] = pageData
                }
            }
        }
    }
    
    private func handleDataChange() async {
        // Invalidate cache and reload current page
        pageCache.removeAll()
        await loadInitialData()
    }
    
    public func refresh() async {
        pageCache.removeAll()
        await loadInitialData()
    }
    
    // Utility methods
    public func item(at index: Int) -> T? {
        guard index >= 0 && index < currentPage.count else { return nil }
        
        // Trigger prefetch if near end
        if index >= currentPage.count - prefetchThreshold {
            Task { await goToNextPage() }
        }
        
        return currentPage[index]
    }
    
    deinit {
        cancellable?.cancel()
    }
}

// Repository extension
extension Repository {
    public func subscribePaginated(query: ORMQueryBuilder<T>? = nil,
                                   pageSize: Int = 20,
                                   prefetchThreshold: Int = 5) -> PaginatedQuerySubscription<T> {
        return PaginatedQuerySubscription(
            repository: self,
            query: query,
            pageSize: pageSize,
            prefetchThreshold: prefetchThreshold
        )
    }
}
```

### 2. Search Subscriptions with Advanced Features

**Use Case:** Real-time search with debouncing, highlighting, and performance optimization.

**Detailed Implementation:**
```swift
@MainActor
public class SearchSubscription<T: ORMTable>: ObservableObject {
    @Published public var searchText: String = "" {
        didSet { scheduleSearch() }
    }
    @Published public private(set) var results: [T] = []
    @Published public private(set) var isSearching: Bool = false
    @Published public private(set) var hasNoResults: Bool = false
    @Published public private(set) var searchDuration: TimeInterval = 0
    @Published public private(set) var resultCount: Int = 0
    
    // Search configuration
    public struct Configuration {
        let searchFields: [String]
        let debounceInterval: TimeInterval
        let minSearchLength: Int
        let maxResults: Int
        let caseSensitive: Bool
        let exactMatch: Bool
        let highlightMatches: Bool
        
        public init(searchFields: [String],
                   debounceInterval: TimeInterval = 0.3,
                   minSearchLength: Int = 2,
                   maxResults: Int = 100,
                   caseSensitive: Bool = false,
                   exactMatch: Bool = false,
                   highlightMatches: Bool = false) {
            self.searchFields = searchFields
            self.debounceInterval = debounceInterval
            self.minSearchLength = minSearchLength
            self.maxResults = maxResults
            self.caseSensitive = caseSensitive
            self.exactMatch = exactMatch
            self.highlightMatches = highlightMatches
        }
    }
    
    private let repository: Repository<T>
    private let configuration: Configuration
    private let baseQuery: ORMQueryBuilder<T>?
    private var searchTask: Task<Void, Never>?
    private var changeNotifier: ChangeNotifier
    private var cancellable: AnyCancellable?
    
    // Performance optimization
    private var searchCache: [String: [T]] = [:]
    private let maxCacheSize: Int = 50
    
    public init(repository: Repository<T>,
                baseQuery: ORMQueryBuilder<T>? = nil,
                configuration: Configuration) {
        self.repository = repository
        self.baseQuery = baseQuery
        self.configuration = configuration
        self.changeNotifier = repository.changeNotifier
        
        Task { await atomicSetup() }
    }
    
    private func atomicSetup() async {
        let publisher = await changeNotifier.publisher(for: T.tableName)
        cancellable = publisher.sink { [weak self] in
            Task { [weak self] in
                await self?.handleDataChange()
            }
        }
    }
    
    private func scheduleSearch() {
        searchTask?.cancel()
        
        guard searchText.count >= configuration.minSearchLength else {
            results = []
            hasNoResults = false
            resultCount = 0
            return
        }
        
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(configuration.debounceInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await performSearch()
            } catch {
                // Task was cancelled - ignore
            }
        }
    }
    
    private func performSearch() async {
        let searchKey = searchText.lowercased()
        
        // Check cache first
        if let cachedResults = searchCache[searchKey] {
            results = Array(cachedResults.prefix(configuration.maxResults))
            resultCount = cachedResults.count
            hasNoResults = results.isEmpty
            return
        }
        
        isSearching = true
        let startTime = Date()
        
        let searchQuery = buildSearchQuery()
        let searchResult = await repository.findAll(query: searchQuery)
        
        let duration = Date().timeIntervalSince(startTime)
        searchDuration = duration
        
        switch searchResult {
        case .success(let searchResults):
            // Cache results
            searchCache[searchKey] = searchResults
            trimCache()
            
            results = Array(searchResults.prefix(configuration.maxResults))
            resultCount = searchResults.count
            hasNoResults = results.isEmpty
            
        case .failure(let error):
            // Handle search error
            results = []
            hasNoResults = true
            print("[SearchSubscription] Search failed: \(error)")
        }
        
        isSearching = false
    }
    
    private func buildSearchQuery() -> ORMQueryBuilder<T> {
        var query = baseQuery ?? ORMQueryBuilder<T>()
        
        let searchTerms = searchText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        guard !searchTerms.isEmpty else { return query }
        
        // Build OR conditions for each field
        var fieldConditions: [String] = []
        
        for field in configuration.searchFields {
            for term in searchTerms {
                let searchValue = configuration.caseSensitive ? term : term.lowercased()
                
                if configuration.exactMatch {
                    fieldConditions.append("\(field) = '\(searchValue)'")
                } else {
                    fieldConditions.append("\(field) LIKE '%\(searchValue)%'")
                }
            }
        }
        
        if !fieldConditions.isEmpty {
            let combinedCondition = fieldConditions.joined(separator: " OR ")
            query = query.whereRaw("(\(combinedCondition))")
        }
        
        return query.limit(configuration.maxResults * 2) // Fetch extra for caching
    }
    
    private func trimCache() {
        guard searchCache.count > maxCacheSize else { return }
        
        // Remove oldest entries (simple LRU approximation)
        let keysToRemove = Array(searchCache.keys.prefix(searchCache.count - maxCacheSize))
        for key in keysToRemove {
            searchCache.removeValue(forKey: key)
        }
    }
    
    private func handleDataChange() async {
        // Invalidate cache and re-run current search
        searchCache.removeAll()
        if !searchText.isEmpty && searchText.count >= configuration.minSearchLength {
            await performSearch()
        }
    }
    
    public func clearSearch() {
        searchText = ""
        results = []
        hasNoResults = false
        resultCount = 0
    }
    
    public func refresh() async {
        searchCache.removeAll()
        await performSearch()
    }
    
    deinit {
        searchTask?.cancel()
        cancellable?.cancel()
    }
}

// Repository extension
extension Repository {
    public func subscribeSearch(baseQuery: ORMQueryBuilder<T>? = nil,
                               configuration: SearchSubscription<T>.Configuration) -> SearchSubscription<T> {
        return SearchSubscription(repository: self, baseQuery: baseQuery, configuration: configuration)
    }
    
    public func subscribeSearch(searchFields: [String],
                               debounceInterval: TimeInterval = 0.3) -> SearchSubscription<T> {
        let config = SearchSubscription<T>.Configuration(
            searchFields: searchFields,
            debounceInterval: debounceInterval
        )
        return subscribeSearch(configuration: config)
    }
}
```

### 3. Grouped Query Subscriptions

**Use Case:** Data that needs to be organized by categories, departments, dates, etc.

**Detailed Implementation:**
```swift
@MainActor
public class GroupedQuerySubscription<T: ORMTable, GroupKey: Hashable & Sendable>: ObservableObject {
    @Published public private(set) var groups: [GroupKey: [T]] = [:]
    @Published public private(set) var sortedGroupKeys: [GroupKey] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: ORMError?
    @Published public private(set) var totalCount: Int = 0
    @Published public private(set) var groupCounts: [GroupKey: Int] = [:]
    
    // Configuration
    public struct Configuration {
        let sortGroupsBy: GroupSortOrder
        let includeEmptyGroups: Bool
        let maxItemsPerGroup: Int?
        
        public enum GroupSortOrder {
            case key(ascending: Bool)
            case count(ascending: Bool)
            case custom((GroupKey, GroupKey) -> Bool)
        }
        
        public init(sortGroupsBy: GroupSortOrder = .key(ascending: true),
                   includeEmptyGroups: Bool = false,
                   maxItemsPerGroup: Int? = nil) {
            self.sortGroupsBy = sortGroupsBy
            self.includeEmptyGroups = includeEmptyGroups
            self.maxItemsPerGroup = maxItemsPerGroup
        }
    }
    
    private let repository: Repository<T>
    private let baseQuery: ORMQueryBuilder<T>?
    private let groupBy: KeyPath<T, GroupKey>
    private let configuration: Configuration
    private var changeNotifier: ChangeNotifier
    private var cancellable: AnyCancellable?
    
    public init(repository: Repository<T>,
                baseQuery: ORMQueryBuilder<T>? = nil,
                groupBy: KeyPath<T, GroupKey>,
                configuration: Configuration = Configuration()) {
        self.repository = repository
        self.baseQuery = baseQuery
        self.groupBy = groupBy
        self.configuration = configuration
        self.changeNotifier = repository.changeNotifier
        
        Task { await atomicSetup() }
    }
    
    private func atomicSetup() async {
        let publisher = await changeNotifier.publisher(for: T.tableName)
        cancellable = publisher.sink { [weak self] in
            Task { [weak self] in
                await self?.refreshData()
            }
        }
        
        await refreshData()
    }
    
    private func refreshData() async {
        isLoading = true
        error = nil
        
        let result = await repository.findAll(query: baseQuery)
        
        switch result {
        case .success(let items):
            await organizeIntoGroups(items)
        case .failure(let error):
            self.error = error
        }
        
        isLoading = false
    }
    
    private func organizeIntoGroups(_ items: [T]) async {
        var newGroups: [GroupKey: [T]] = [:]
        var newGroupCounts: [GroupKey: Int] = [:]
        
        // Group items by key
        for item in items {
            let key = item[keyPath: groupBy]
            
            if newGroups[key] == nil {
                newGroups[key] = []
            }
            
            // Apply per-group limit if specified
            if let maxItems = configuration.maxItemsPerGroup,
               newGroups[key]!.count >= maxItems {
                continue
            }
            
            newGroups[key]!.append(item)
            newGroupCounts[key] = (newGroupCounts[key] ?? 0) + 1
        }
        
        // Sort groups according to configuration
        let sortedKeys = sortGroupKeys(Array(newGroups.keys), counts: newGroupCounts)
        
        // Update published properties
        groups = newGroups
        sortedGroupKeys = sortedKeys
        groupCounts = newGroupCounts
        totalCount = items.count
    }
    
    private func sortGroupKeys(_ keys: [GroupKey], counts: [GroupKey: Int]) -> [GroupKey] {
        switch configuration.sortGroupsBy {
        case .key(let ascending):
            return keys.sorted { ascending ? $0 < $1 : $0 > $1 }
            
        case .count(let ascending):
            return keys.sorted { key1, key2 in
                let count1 = counts[key1] ?? 0
                let count2 = counts[key2] ?? 0
                return ascending ? count1 < count2 : count1 > count2
            }
            
        case .custom(let comparator):
            return keys.sorted(by: comparator)
        }
    }
    
    // Public API
    public func items(in group: GroupKey) -> [T] {
        return groups[group] ?? []
    }
    
    public func count(in group: GroupKey) -> Int {
        return groupCounts[group] ?? 0
    }
    
    public func hasItems(in group: GroupKey) -> Bool {
        return count(in: group) > 0
    }
    
    public func refresh() async {
        await refreshData()
    }
    
    deinit {
        cancellable?.cancel()
    }
}

// Repository extension
extension Repository {
    public func subscribeGrouped<GroupKey: Hashable & Sendable>(
        baseQuery: ORMQueryBuilder<T>? = nil,
        groupBy: KeyPath<T, GroupKey>,
        configuration: GroupedQuerySubscription<T, GroupKey>.Configuration = .init()
    ) -> GroupedQuerySubscription<T, GroupKey> {
        return GroupedQuerySubscription(
            repository: self,
            baseQuery: baseQuery,
            groupBy: groupBy,
            configuration: configuration
        )
    }
}
```

## Phase 2: Smart Change Notification System

### Enhanced ChangeNotifier with Row-Level Tracking

**Current Problem:** Table-level notifications trigger all subscriptions, causing unnecessary refreshes.

**Solution:** Row-level change tracking with smart filtering.

```swift
public actor SmartChangeNotifier {
    // Change event types
    public enum ChangeEvent: Sendable {
        case inserted(tableName: String, id: AnySendable, newData: [String: AnySendable])
        case updated(tableName: String, id: AnySendable, changes: [String: AnySendable])
        case deleted(tableName: String, id: AnySendable)
        case bulkChange(tableName: String, affectedCount: Int)
        case schemaChange(tableName: String)
    }
    
    // Subscription filters
    public enum SubscriptionFilter: Sendable {
        case all
        case rowIds([AnySendable])
        case affectsFields([String])
        case queryRelevant(ORMQueryBuilder<any ORMTable>)
        case custom(@Sendable (ChangeEvent) -> Bool)
    }
    
    private var tablePublishers: [String: PassthroughSubject<ChangeEvent, Never>] = [:]
    private var subscriptionFilters: [UUID: (String, SubscriptionFilter)] = [:]
    
    // Enhanced publisher with filtering
    public func publisher(for tableName: String, 
                         filter: SubscriptionFilter = .all) -> (AnyPublisher<ChangeEvent, Never>, UUID) {
        let subscriptionId = UUID()
        subscriptionFilters[subscriptionId] = (tableName, filter)
        
        if tablePublishers[tableName] == nil {
            tablePublishers[tableName] = PassthroughSubject<ChangeEvent, Never>()
        }
        
        let filteredPublisher = tablePublishers[tableName]!
            .filter { [weak self] event in
                self?.shouldNotifySubscription(subscriptionId, for: event) ?? true
            }
            .eraseToAnyPublisher()
        
        return (filteredPublisher, subscriptionId)
    }
    
    public func removeSubscription(_ id: UUID) {
        subscriptionFilters.removeValue(forKey: id)
    }
    
    private func shouldNotifySubscription(_ subscriptionId: UUID, for event: ChangeEvent) -> Bool {
        guard let (tableName, filter) = subscriptionFilters[subscriptionId] else { return false }
        
        // Ensure event is for the right table
        guard event.tableName == tableName else { return false }
        
        switch filter {
        case .all:
            return true
            
        case .rowIds(let targetIds):
            return targetIds.contains { $0.base as AnyHashable == event.id.base as AnyHashable }
            
        case .affectsFields(let fields):
            switch event {
            case .updated(_, _, let changes):
                return !Set(changes.keys).isDisjoint(with: Set(fields))
            case .inserted, .deleted:
                return true // Always relevant for insertions/deletions
            case .bulkChange, .schemaChange:
                return true // Conservative approach
            }
            
        case .queryRelevant(let query):
            // This would require query analysis - complex but powerful
            return true // Fallback to always notify
            
        case .custom(let predicate):
            return predicate(event)
        }
    }
    
    // Enhanced notification methods
    public func notifyInsert<T: ORMTable>(tableName: String, model: T) {
        let event = ChangeEvent.inserted(
            tableName: tableName,
            id: AnySendable(model.id),
            newData: extractFields(from: model)
        )
        tablePublishers[tableName]?.send(event)
    }
    
    public func notifyUpdate<T: ORMTable>(tableName: String, id: T.IDType, changes: [String: Any]) {
        let event = ChangeEvent.updated(
            tableName: tableName,
            id: AnySendable(id),
            changes: changes.mapValues(AnySendable.init)
        )
        tablePublishers[tableName]?.send(event)
    }
    
    public func notifyDelete<T: ORMTable>(tableName: String, id: T.IDType) {
        let event = ChangeEvent.deleted(
            tableName: tableName,
            id: AnySendable(id)
        )
        tablePublishers[tableName]?.send(event)
    }
    
    private func extractFields<T: ORMTable>(from model: T) -> [String: AnySendable] {
        // Use reflection or predefined mappings to extract field values
        // This would need to be implemented based on the ORM's field mapping system
        return [:]
    }
}

// Type-erased sendable wrapper
public struct AnySendable: Sendable, Hashable {
    public let base: Any
    private let _hashValue: Int
    private let _isEqual: (Any) -> Bool
    
    public init<T: Sendable & Hashable>(_ value: T) {
        self.base = value
        self._hashValue = value.hashValue
        self._isEqual = { other in
            guard let otherT = other as? T else { return false }
            return value == otherT
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(_hashValue)
    }
    
    public static func == (lhs: AnySendable, rhs: AnySendable) -> Bool {
        return lhs._isEqual(rhs.base)
    }
}
```

### Enhanced Subscription Base with Smart Notifications

```swift
@MainActor
public class SmartSubscriptionBase<T: ORMTable>: ObservableObject {
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: ORMError?
    @Published public private(set) var lastRefreshTime: Date?
    
    protected let repository: Repository<T>
    protected let query: ORMQueryBuilder<T>?
    private let smartNotifier: SmartChangeNotifier
    private var subscriptionId: UUID?
    private var cancellable: AnyCancellable?
    
    // Performance metrics
    public private(set) var refreshCount: Int = 0
    public private(set) var averageRefreshTime: TimeInterval = 0
    
    public init(repository: Repository<T>, query: ORMQueryBuilder<T>?) {
        self.repository = repository
        self.query = query
        self.smartNotifier = repository.smartChangeNotifier
    }
    
    protected func setupSmartNotifications(filter: SmartChangeNotifier.SubscriptionFilter = .all) async {
        let (publisher, id) = await smartNotifier.publisher(for: T.tableName, filter: filter)
        subscriptionId = id
        
        cancellable = publisher.sink { [weak self] event in
            Task { [weak self] in
                await self?.handleSmartChange(event)
            }
        }
        
        await performInitialLoad()
    }
    
    private func handleSmartChange(_ event: SmartChangeNotifier.ChangeEvent) async {
        // Only refresh if the change is actually relevant
        if await shouldRefreshForChange(event) {
            await refreshData()
        }
    }
    
    protected func shouldRefreshForChange(_ event: SmartChangeNotifier.ChangeEvent) async -> Bool {
        // Override in subclasses for specific logic
        return true
    }
    
    protected func performInitialLoad() async {
        await refreshData()
    }
    
    protected func refreshData() async {
        let startTime = Date()
        isLoading = true
        error = nil
        
        defer {
            isLoading = false
            lastRefreshTime = Date()
            refreshCount += 1
            
            let refreshTime = Date().timeIntervalSince(startTime)
            averageRefreshTime = (averageRefreshTime * Double(refreshCount - 1) + refreshTime) / Double(refreshCount)
        }
        
        await performDataRefresh()
    }
    
    // Override in subclasses
    protected func performDataRefresh() async {
        fatalError("Must be overridden")
    }
    
    deinit {
        if let id = subscriptionId {
            Task {
                await smartNotifier.removeSubscription(id)
            }
        }
        cancellable?.cancel()
    }
}
```

## Phase 3: Subscription Composition and Architecture

### Subscription Factory and Registry

```swift
// Protocol for all subscription types
public protocol QuerySubscriptionProtocol: ObservableObject {
    associatedtype Model: ORMTable
    associatedtype Configuration
    
    init(repository: Repository<Model>, 
         query: ORMQueryBuilder<Model>?, 
         configuration: Configuration)
    
    func refresh() async
    var isLoading: Bool { get }
    var error: ORMError? { get }
}

// Factory for creating subscriptions
public class SubscriptionFactory {
    public static func create<S: QuerySubscriptionProtocol>(
        _ subscriptionType: S.Type,
        repository: Repository<S.Model>,
        query: ORMQueryBuilder<S.Model>? = nil,
        configuration: S.Configuration
    ) -> S {
        return S(repository: repository, query: query, configuration: configuration)
    }
}

// Registry for managing active subscriptions
@MainActor
public class SubscriptionRegistry: ObservableObject {
    public static let shared = SubscriptionRegistry()
    
    private var activeSubscriptions: [String: WeakSubscriptionWrapper] = [:]
    private var subscriptionMetrics: [String: SubscriptionMetrics] = [:]
    
    private init() {
        // Start cleanup timer
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { await self.cleanup() }
        }
    }
    
    public func register<T: ObservableObject>(_ subscription: T, 
                                            identifier: String? = nil) -> String {
        let id = identifier ?? UUID().uuidString
        activeSubscriptions[id] = WeakSubscriptionWrapper(subscription)
        
        // Initialize metrics
        subscriptionMetrics[id] = SubscriptionMetrics(
            id: id,
            type: String(describing: type(of: subscription)),
            createdAt: Date()
        )
        
        return id
    }
    
    public func unregister(_ id: String) {
        activeSubscriptions.removeValue(forKey: id)
        subscriptionMetrics.removeValue(forKey: id)
    }
    
    private func cleanup() {
        let beforeCount = activeSubscriptions.count
        
        activeSubscriptions = activeSubscriptions.compactMapValues { wrapper in
            wrapper.subscription != nil ? wrapper : nil
        }
        
        let afterCount = activeSubscriptions.count
        if beforeCount != afterCount {
            print("[SubscriptionRegistry] Cleaned up \(beforeCount - afterCount) deallocated subscriptions")
        }
    }
    
    // Debug and monitoring
    public var activeSubscriptionCount: Int {
        return activeSubscriptions.count
    }
    
    public func getMetrics() -> [SubscriptionMetrics] {
        return Array(subscriptionMetrics.values)
    }
    
    public func getDebugInfo() -> [SubscriptionDebugInfo] {
        return activeSubscriptions.compactMap { (id, wrapper) in
            guard let subscription = wrapper.subscription else { return nil }
            
            return SubscriptionDebugInfo(
                id: id,
                type: String(describing: type(of: subscription)),
                isActive: true,
                createdAt: subscriptionMetrics[id]?.createdAt ?? Date(),
                memoryUsage: estimateMemoryUsage(subscription)
            )
        }
    }
    
    private func estimateMemoryUsage<T: AnyObject>(_ object: T) -> Int {
        return MemoryLayout.size(ofValue: object)
    }
}

// Supporting types
private class WeakSubscriptionWrapper {
    weak var subscription: AnyObject?
    
    init(_ subscription: AnyObject) {
        self.subscription = subscription
    }
}

public struct SubscriptionMetrics: Sendable {
    public let id: String
    public let type: String
    public let createdAt: Date
    public var refreshCount: Int = 0
    public var totalRefreshTime: TimeInterval = 0
    public var lastRefreshTime: Date?
    
    public var averageRefreshTime: TimeInterval {
        guard refreshCount > 0 else { return 0 }
        return totalRefreshTime / Double(refreshCount)
    }
}

public struct SubscriptionDebugInfo: Sendable {
    public let id: String
    public let type: String
    public let isActive: Bool
    public let createdAt: Date
    public let memoryUsage: Int
}
```

### Subscription Composition with Result Builder

```swift
// Result builder for composing subscriptions
@resultBuilder
public struct SubscriptionBuilder {
    public static func buildBlock(_ subscriptions: any ObservableObject...) -> [any ObservableObject] {
        return Array(subscriptions)
    }
    
    public static func buildOptional(_ subscription: (any ObservableObject)?) -> [any ObservableObject] {
        return subscription.map { [$0] } ?? []
    }
    
    public static func buildEither(first: [any ObservableObject]) -> [any ObservableObject] {
        return first
    }
    
    public static func buildEither(second: [any ObservableObject]) -> [any ObservableObject] {
        return second
    }
    
    public static func buildArray(_ subscriptions: [[any ObservableObject]]) -> [any ObservableObject] {
        return subscriptions.flatMap { $0 }
    }
}

// Combined subscription manager
@MainActor
public class CombinedSubscription: ObservableObject {
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var hasErrors: Bool = false
    @Published public private(set) var loadingProgress: Double = 0.0
    
    private let subscriptions: [any ObservableObject]
    private var cancellables: Set<AnyCancellable> = []
    private var loadingStates: [Bool] = []
    
    public init(@SubscriptionBuilder _ builder: () -> [any ObservableObject]) {
        self.subscriptions = builder()
        self.loadingStates = Array(repeating: false, count: subscriptions.count)
        setupObservation()
    }
    
    private func setupObservation() {
        for (index, subscription) in subscriptions.enumerated() {
            // Observe loading state if available
            if let loadingPublisher = (subscription as? any LoadingStateProvider)?.isLoadingPublisher {
                loadingPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] isLoading in
                        self?.updateLoadingState(at: index, isLoading: isLoading)
                    }
                    .store(in: &cancellables)
            }
            
            // Observe error state if available
            if let errorPublisher = (subscription as? any ErrorStateProvider)?.errorPublisher {
                errorPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] error in
                        self?.updateErrorState(error != nil)
                    }
                    .store(in: &cancellables)
            }
        }
    }
    
    private func updateLoadingState(at index: Int, isLoading: Bool) {
        guard index < loadingStates.count else { return }
        
        loadingStates[index] = isLoading
        
        let loadingCount = loadingStates.filter { $0 }.count
        self.isLoading = loadingCount > 0
        self.loadingProgress = loadingCount > 0 ? 
            Double(loadingStates.count - loadingCount) / Double(loadingStates.count) : 1.0
    }
    
    private func updateErrorState(_ hasError: Bool) {
        self.hasErrors = hasError
    }
    
    public func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for subscription in subscriptions {
                if let refreshable = subscription as? any RefreshableSubscription {
                    group.addTask {
                        await refreshable.refresh()
                    }
                }
            }
        }
    }
}

// Supporting protocols
public protocol LoadingStateProvider {
    var isLoadingPublisher: AnyPublisher<Bool, Never> { get }
}

public protocol ErrorStateProvider {
    var errorPublisher: AnyPublisher<Error?, Never> { get }
}

public protocol RefreshableSubscription {
    func refresh() async
}

// Extensions to make existing subscriptions compatible
extension QuerySubscription: LoadingStateProvider, ErrorStateProvider, RefreshableSubscription {
    public var isLoadingPublisher: AnyPublisher<Bool, Never> {
        $isLoading.eraseToAnyPublisher()
    }
    
    public var errorPublisher: AnyPublisher<Error?, Never> {
        $error.map { $0 as Error? }.eraseToAnyPublisher()
    }
}
```

## Phase 4: SwiftUI Integration and Developer Experience

### Property Wrappers for Simplified Usage

```swift
// Property wrapper for query subscriptions
@propertyWrapper
public struct QuerySubscribe<T: ORMTable>: DynamicProperty {
    @StateObject private var subscription: QuerySubscription<T>
    
    public init(repository: Repository<T>, query: ORMQueryBuilder<T>? = nil) {
        self._subscription = StateObject(wrappedValue: QuerySubscription(
            repository: repository,
            query: query
        ))
    }
    
    public var wrappedValue: ORMResult<[T]> {
        subscription.result
    }
    
    public var projectedValue: QuerySubscription<T> {
        subscription
    }
}

// Property wrapper for search subscriptions
@propertyWrapper
public struct SearchSubscribe<T: ORMTable>: DynamicProperty {
    @StateObject private var subscription: SearchSubscription<T>
    
    public init(repository: Repository<T>, 
                searchFields: [String],
                debounceInterval: TimeInterval = 0.3) {
        let config = SearchSubscription<T>.Configuration(
            searchFields: searchFields,
            debounceInterval: debounceInterval
        )
        self._subscription = StateObject(wrappedValue: SearchSubscription(
            repository: repository,
            configuration: config
        ))
    }
    
    public var wrappedValue: [T] {
        subscription.results
    }
    
    public var projectedValue: SearchSubscription<T> {
        subscription
    }
}

// Property wrapper for paginated subscriptions
@propertyWrapper
public struct PaginatedSubscribe<T: ORMTable>: DynamicProperty {
    @StateObject private var subscription: PaginatedQuerySubscription<T>
    
    public init(repository: Repository<T>, 
                query: ORMQueryBuilder<T>? = nil,
                pageSize: Int = 20) {
        self._subscription = StateObject(wrappedValue: PaginatedQuerySubscription(
            repository: repository,
            query: query,
            pageSize: pageSize
        ))
    }
    
    public var wrappedValue: [T] {
        subscription.currentPage
    }
    
    public var projectedValue: PaginatedQuerySubscription<T> {
        subscription
    }
}
```

### SwiftUI View Modifiers

```swift
// View modifiers for common subscription patterns
extension View {
    public func withSubscriptionLoading<T: ObservableObject & LoadingStateProvider>(
        _ subscription: T
    ) -> some View {
        self.overlay(
            Group {
                if subscription.isLoadingPublisher {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                        .background(Color.black.opacity(0.1))
                }
            }
        )
    }
    
    public func withSubscriptionError<T: ObservableObject & ErrorStateProvider>(
        _ subscription: T,
        action: @escaping () -> Void = {}
    ) -> some View {
        self.alert("Error", isPresented: .constant(subscription.errorPublisher != nil)) {
            Button("Retry", action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(subscription.errorPublisher?.localizedDescription ?? "An error occurred")
        }
    }
    
    public func withRefreshable<T: ObservableObject & RefreshableSubscription>(
        _ subscription: T
    ) -> some View {
        self.refreshable {
            await subscription.refresh()
        }
    }
}
```

### Example Usage in SwiftUI

```swift
struct ModernUserListView: View {
    @QuerySubscribe(repository: userRepository) var users
    @SearchSubscribe(repository: userRepository, searchFields: ["username", "email"]) var searchResults
    @PaginatedSubscribe(repository: userRepository, pageSize: 50) var paginatedUsers
    
    @State private var isSearching = false
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $searchResults.searchText, isSearching: $isSearching)
                
                if isSearching && !$searchResults.searchText.wrappedValue.isEmpty {
                    SearchResultsList(results: searchResults)
                } else {
                    PaginatedUserList(subscription: $paginatedUsers)
                }
            }
            .navigationTitle("Users")
            .withSubscriptionLoading($users)
            .withSubscriptionError($users) {
                Task { await $users.refresh() }
            }
            .withRefreshable($users)
        }
    }
}

struct SearchResultsList: View {
    let results: [User]
    
    var body: some View {
        List(results, id: \.id) { user in
            UserRowView(user: user)
        }
    }
}

struct PaginatedUserList: View {
    @Binding var subscription: PaginatedQuerySubscription<User>
    
    var body: some View {
        List {
            ForEach(subscription.currentPage, id: \.id) { user in
                UserRowView(user: user)
                    .onAppear {
                        // Auto-load next page when approaching end
                        if user.id == subscription.currentPage.last?.id {
                            Task {
                                await subscription.goToNextPage()
                            }
                        }
                    }
            }
            
            if subscription.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button("Previous") {
                        Task { await subscription.goToPreviousPage() }
                    }
                    .disabled(!subscription.hasPreviousPage)
                    
                    Spacer()
                    
                    Text("Page \(subscription.currentPageIndex + 1) of \(subscription.totalPages)")
                        .font(.caption)
                    
                    Spacer()
                    
                    Button("Next") {
                        Task { await subscription.goToNextPage() }
                    }
                    .disabled(!subscription.hasNextPage)
                }
            }
        }
    }
}
```

## Implementation Strategy

### Git Branch Strategy

```bash
# Create feature branch for subscription enhancements
git checkout -b feature/subscription-enhancements

# Sub-branches for each phase
git checkout -b feature/subscription-naming-refactor
git checkout -b feature/advanced-subscriptions
git checkout -b feature/smart-notifications
git checkout -b feature/subscription-composition
git checkout -b feature/swiftui-integration
```

### Development Phases

1. **Phase 0 (Week 1)**: Naming refactor and compatibility
   - Implement hybrid naming approach
   - Add deprecation warnings
   - Update documentation

2. **Phase 1 (Weeks 2-4)**: Advanced subscription types
   - PaginatedQuerySubscription
   - SearchSubscription
   - GroupedQuerySubscription
   - AggregationSubscription

3. **Phase 2 (Weeks 5-6)**: Smart change notifications
   - SmartChangeNotifier
   - Row-level tracking
   - Subscription filtering

4. **Phase 3 (Weeks 7-8)**: Composition and architecture
   - Subscription factory
   - Registry and monitoring
   - Composition with result builders

5. **Phase 4 (Weeks 9-10)**: SwiftUI integration
   - Property wrappers
   - View modifiers
   - Example implementations

### Testing Strategy

1. **Unit Tests**: Each subscription type gets comprehensive test coverage
2. **Integration Tests**: Test subscription interactions with database changes
3. **Performance Tests**: Measure memory usage and refresh times
4. **SwiftUI Tests**: Snapshot and UI testing for SwiftUI components
5. **Backwards Compatibility Tests**: Ensure existing code continues working

### Documentation Plan

1. **Migration Guide**: How to update from "Simple" to new names
2. **Advanced Subscriptions Guide**: When and how to use each type
3. **Performance Best Practices**: Optimization tips and patterns
4. **SwiftUI Integration Examples**: Complete example apps
5. **API Reference**: Comprehensive documentation for all new types

This enhancement plan transforms SwiftSync from a basic reactive data layer into a comprehensive, modern, and robust framework that can handle any subscription pattern while maintaining the excellent foundation that already exists.