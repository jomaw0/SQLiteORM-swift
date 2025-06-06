import Foundation
@preconcurrency import Combine

/// A simple and robust Combine publisher for SQLiteORM query subscriptions
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@MainActor
public final class SimpleQuerySubscription<T: ORMTable>: ObservableObject {
    @Published public private(set) var result: ORMResult<[T]> = .success([])
    
    private let repository: Repository<T>
    private let query: ORMQueryBuilder<T>?
    private let changeNotifier: ChangeNotifier
    private var cancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    // Readiness tracking
    private let isReady = CurrentValueSubject<Bool, Never>(false)
    
    /// Initialize a new query subscription
    /// - Parameters:
    ///   - repository: The repository to query
    ///   - query: Optional query builder to filter results
    ///   - changeNotifier: The change notification system
    public nonisolated init(repository: Repository<T>, query: ORMQueryBuilder<T>?, changeNotifier: ChangeNotifier) {
        self.repository = repository
        self.query = query
        self.changeNotifier = changeNotifier
        
        Task {
            await setupSubscription()
        }
    }
    
    deinit {
        cancellable?.cancel()
        isReady.send(completion: .finished)
    }
    
    /// Wait for the subscription to complete its initial data load
    /// This ensures that the subscription has loaded initial data before proceeding
    public func waitForInitialization() async {
        await withCheckedContinuation { continuation in
            isReady
                .filter { $0 }
                .first()
                .sink { _ in
                    continuation.resume()
                }
                .store(in: &cancellables)
        }
    }
    
    private func setupSubscription() async {
        // Load initial data
        await refreshData()
        
        // Mark as ready AFTER initial data is loaded
        await MainActor.run {
            isReady.value = true
        }
        
        // Subscribe to changes
        let publisher = await changeNotifier.publisher(for: T.tableName)
        cancellable = publisher
            .sink { [weak self] in
                Task { [weak self] in
                    await self?.refreshData()
                }
            }
    }
    
    private func refreshData() async {
        let newResult = await repository.findAll(query: query)
        await MainActor.run {
            result = newResult
        }
    }
}

/// A simple subscription for single model queries
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@MainActor
public final class SimpleSingleQuerySubscription<T: ORMTable>: ObservableObject {
    @Published public private(set) var result: ORMResult<T?> = .success(nil)
    
    private let repository: Repository<T>
    private let query: ORMQueryBuilder<T>
    private let changeNotifier: ChangeNotifier
    private var cancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    // Readiness tracking
    private let isReady = CurrentValueSubject<Bool, Never>(false)
    
    /// Initialize a new single query subscription
    /// - Parameters:
    ///   - repository: The repository to query
    ///   - query: Query builder to find the model
    ///   - changeNotifier: The change notification system
    public nonisolated init(repository: Repository<T>, query: ORMQueryBuilder<T>, changeNotifier: ChangeNotifier) {
        self.repository = repository
        self.query = query
        self.changeNotifier = changeNotifier
        
        Task {
            await setupSubscription()
        }
    }
    
    deinit {
        cancellable?.cancel()
        isReady.send(completion: .finished)
    }
    
    /// Wait for the subscription to complete its initial data load
    /// This ensures that the subscription has loaded initial data before proceeding
    public func waitForInitialization() async {
        await withCheckedContinuation { continuation in
            isReady
                .filter { $0 }
                .first()
                .sink { _ in
                    continuation.resume()
                }
                .store(in: &cancellables)
        }
    }
    
    private func setupSubscription() async {
        // Load initial data
        await refreshData()
        
        // Mark as ready AFTER initial data is loaded
        await MainActor.run {
            isReady.value = true
        }
        
        // Subscribe to changes
        let publisher = await changeNotifier.publisher(for: T.tableName)
        cancellable = publisher
            .sink { [weak self] in
                Task { [weak self] in
                    await self?.refreshData()
                }
            }
    }
    
    private func refreshData() async {
        let newResult = await repository.findFirst(query: query)
        await MainActor.run {
            result = newResult
        }
    }
}

/// A simple subscription for count queries
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@MainActor
public final class SimpleCountSubscription<T: ORMTable>: ObservableObject {
    @Published public private(set) var result: ORMResult<Int> = .success(0)
    
    private let repository: Repository<T>
    private let query: ORMQueryBuilder<T>?
    private let changeNotifier: ChangeNotifier
    private var cancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    // Readiness tracking
    private let isReady = CurrentValueSubject<Bool, Never>(false)
    
    /// Initialize a new count subscription
    /// - Parameters:
    ///   - repository: The repository to query
    ///   - query: Optional query builder to filter the count
    ///   - changeNotifier: The change notification system
    public nonisolated init(repository: Repository<T>, query: ORMQueryBuilder<T>?, changeNotifier: ChangeNotifier) {
        self.repository = repository
        self.query = query
        self.changeNotifier = changeNotifier
        
        Task {
            await setupSubscription()
        }
    }
    
    deinit {
        cancellable?.cancel()
        isReady.send(completion: .finished)
    }
    
    /// Wait for the subscription to complete its initial data load
    /// This ensures that the subscription has loaded initial data before proceeding
    public func waitForInitialization() async {
        await withCheckedContinuation { continuation in
            isReady
                .filter { $0 }
                .first()
                .sink { _ in
                    continuation.resume()
                }
                .store(in: &cancellables)
        }
    }
    
    private func setupSubscription() async {
        // Load initial data
        await refreshData()
        
        // Mark as ready AFTER initial data is loaded
        await MainActor.run {
            isReady.value = true
        }
        
        // Subscribe to changes
        let publisher = await changeNotifier.publisher(for: T.tableName)
        cancellable = publisher
            .sink { [weak self] in
                Task { [weak self] in
                    await self?.refreshData()
                }
            }
    }
    
    private func refreshData() async {
        let newResult = await repository.count(query: query)
        await MainActor.run {
            result = newResult
        }
    }
}