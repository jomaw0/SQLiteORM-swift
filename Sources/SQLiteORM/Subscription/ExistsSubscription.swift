import Foundation
@preconcurrency import Combine

/// A robust Combine publisher for existence-based SQLiteORM subscriptions
/// Uses atomic setup to eliminate race conditions without complex state tracking
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@MainActor
public final class ExistsSubscription<T: ORMTable>: ObservableObject {
    @Published public private(set) var result: ORMResult<Bool> = .success(false)
    
    private let repository: Repository<T>
    private let query: ORMQueryBuilder<T>?
    private let changeNotifier: ChangeNotifier
    private var cancellable: AnyCancellable?
    
    /// Initialize a new existence subscription with immediate atomic setup
    /// - Parameters:
    ///   - repository: The repository to query
    ///   - query: Optional query builder to filter the existence check
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
        
        // Step 2: Load initial data
        await refreshData()
    }
    
    /// Refresh data from repository
    private func refreshData() async {
        let countResult = await repository.count(query: query)
        let existsResult = countResult.map { count in count > 0 }
        self.result = existsResult
    }
    
    /// Manually refresh the subscription data
    public func refresh() async {
        await refreshData()
    }
    
    /// Convenience access to existence boolean (false if error)
    public var exists: Bool {
        switch result {
        case .success(let exists):
            return exists
        case .failure:
            return false
        }
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
