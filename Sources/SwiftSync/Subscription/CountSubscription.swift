import Foundation
@preconcurrency import Combine

/// A robust Combine publisher for count query SwiftSync subscriptions
/// Uses atomic setup to eliminate race conditions without complex state tracking
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@MainActor
public final class CountSubscription<T: ORMTable>: ObservableObject {
    @Published public private(set) var result: ORMResult<Int> = .success(0)
    
    private let repository: Repository<T>
    private let query: ORMQueryBuilder<T>?
    private let changeNotifier: ChangeNotifier
    private var cancellable: AnyCancellable?
    
    /// Initialize a new count subscription with immediate atomic setup
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
        self.result = countResult
    }
    
    /// Manually refresh the subscription data
    public func refresh() async {
        await refreshData()
    }
    
    /// Convenience access to count value (0 if error)
    public var count: Int {
        switch result {
        case .success(let count):
            return count
        case .failure:
            return 0
        }
    }
    
    /// Check if count is greater than zero
    public var hasItems: Bool {
        return count > 0
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

