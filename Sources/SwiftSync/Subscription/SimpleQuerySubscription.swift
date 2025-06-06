import Foundation
@preconcurrency import Combine

/// A robust Combine publisher for SwiftSync query subscriptions
/// Uses atomic setup to eliminate race conditions without complex state tracking
/// 
/// - Note: This class is deprecated. Use `QuerySubscription` instead.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@available(*, deprecated, renamed: "QuerySubscription", message: "Use QuerySubscription instead. SimpleQuerySubscription will be removed in a future version.")
@MainActor
public final class SimpleQuerySubscription<T: ORMTable>: ObservableObject {
    @Published public private(set) var result: ORMResult<[T]> = .success([])
    
    private let repository: Repository<T>
    private let query: ORMQueryBuilder<T>?
    private let changeNotifier: ChangeNotifier
    private var cancellable: AnyCancellable?
    
    /// Initialize a new query subscription with immediate atomic setup
    /// - Parameters:
    ///   - repository: The repository to query
    ///   - query: Optional query builder to filter results
    ///   - changeNotifier: The change notification system
    public nonisolated init(repository: Repository<T>, query: ORMQueryBuilder<T>?, changeNotifier: ChangeNotifier) {
        self.repository = repository
        self.query = query
        self.changeNotifier = changeNotifier
        
        // Immediate atomic setup - eliminates race conditions
        Task { @MainActor in
            await self.atomicSetup()
        }
    }
    
    deinit {
        cancellable?.cancel()
    }
    
    /// Atomic setup: subscribe to changes BEFORE loading data
    /// This eliminates race conditions by ensuring any changes during data loading trigger refresh
    private func atomicSetup() async {
        // Step 1: Subscribe to changes FIRST - before loading any data
        let publisher = await changeNotifier.publisher(for: T.tableName)
        cancellable = publisher.sink { [weak self] in
            Task { [weak self] in
                await self?.refreshData()
            }
        }
        
        // Step 2: THEN load initial data
        // Any concurrent changes will automatically trigger refresh via the subscription above
        await refreshData()
    }
    
    private func refreshData() async {
        let newResult = await repository.findAll(query: query)
        await MainActor.run {
            result = newResult
        }
    }
}

/// A subscription for single model queries
/// Uses atomic setup to eliminate race conditions
/// 
/// - Note: This class is deprecated. Use `SingleQuerySubscription` instead.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@available(*, deprecated, renamed: "SingleQuerySubscription", message: "Use SingleQuerySubscription instead. SimpleSingleQuerySubscription will be removed in a future version.")
@MainActor
public final class SimpleSingleQuerySubscription<T: ORMTable>: ObservableObject {
    @Published public private(set) var result: ORMResult<T?> = .success(nil)
    
    private let repository: Repository<T>
    private let query: ORMQueryBuilder<T>
    private let changeNotifier: ChangeNotifier
    private var cancellable: AnyCancellable?
    
    /// Initialize a new single query subscription with immediate atomic setup
    /// - Parameters:
    ///   - repository: The repository to query
    ///   - query: Query builder to find the model
    ///   - changeNotifier: The change notification system
    public nonisolated init(repository: Repository<T>, query: ORMQueryBuilder<T>, changeNotifier: ChangeNotifier) {
        self.repository = repository
        self.query = query
        self.changeNotifier = changeNotifier
        
        // Immediate atomic setup - eliminates race conditions
        Task { @MainActor in
            await self.atomicSetup()
        }
    }
    
    deinit {
        cancellable?.cancel()
    }
    
    /// Atomic setup: subscribe to changes BEFORE loading data
    private func atomicSetup() async {
        // Step 1: Subscribe to changes FIRST
        let publisher = await changeNotifier.publisher(for: T.tableName)
        cancellable = publisher.sink { [weak self] in
            Task { [weak self] in
                await self?.refreshData()
            }
        }
        
        // Step 2: THEN load initial data
        await refreshData()
    }
    
    private func refreshData() async {
        let newResult = await repository.findFirst(query: query)
        await MainActor.run {
            result = newResult
        }
    }
}

/// A subscription for count queries
/// Uses atomic setup to eliminate race conditions
/// 
/// - Note: This class is deprecated. Use `CountSubscription` instead.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@available(*, deprecated, renamed: "CountSubscription", message: "Use CountSubscription instead. SimpleCountSubscription will be removed in a future version.")
@MainActor
public final class SimpleCountSubscription<T: ORMTable>: ObservableObject {
    @Published public private(set) var result: ORMResult<Int> = .success(0)
    
    private let repository: Repository<T>
    private let query: ORMQueryBuilder<T>?
    private let changeNotifier: ChangeNotifier
    private var cancellable: AnyCancellable?
    
    /// Initialize a new count subscription with immediate atomic setup
    /// - Parameters:
    ///   - repository: The repository to query
    ///   - query: Optional query builder to filter the count
    ///   - changeNotifier: The change notification system
    public nonisolated init(repository: Repository<T>, query: ORMQueryBuilder<T>?, changeNotifier: ChangeNotifier) {
        self.repository = repository
        self.query = query
        self.changeNotifier = changeNotifier
        
        // Immediate atomic setup - eliminates race conditions
        Task { @MainActor in
            await self.atomicSetup()
        }
    }
    
    deinit {
        cancellable?.cancel()
    }
    
    /// Atomic setup: subscribe to changes BEFORE loading data
    private func atomicSetup() async {
        // Step 1: Subscribe to changes FIRST
        let publisher = await changeNotifier.publisher(for: T.tableName)
        cancellable = publisher.sink { [weak self] in
            Task { [weak self] in
                await self?.refreshData()
            }
        }
        
        // Step 2: THEN load initial data
        await refreshData()
    }
    
    private func refreshData() async {
        let newResult = await repository.count(query: query)
        await MainActor.run {
            result = newResult
        }
    }
}