import Foundation
@preconcurrency import Combine

/// A robust Combine publisher for SwiftSync query subscriptions
/// Uses atomic setup to eliminate race conditions without complex state tracking
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@MainActor
public final class QuerySubscription<T: ORMTable>: ObservableObject {
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
    
    /// Refresh data from repository
    private func refreshData() async {
        let fetchResult = await repository.findAll(query: query)
        self.result = fetchResult
    }
    
    /// Manually refresh the subscription data
    public func refresh() async {
        await refreshData()
    }
    
    /// Convenience access to successful results
    public var items: [T] {
        switch result {
        case .success(let items):
            return items
        case .failure:
            return []
        }
    }
    
    /// Check if subscription has data
    public var hasItems: Bool {
        return !items.isEmpty
    }
    
    /// Get error if subscription failed
    public var error: ORMError? {
        switch result {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }
}

