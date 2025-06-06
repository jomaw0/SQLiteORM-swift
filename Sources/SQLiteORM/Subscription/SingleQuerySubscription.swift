import Foundation
@preconcurrency import Combine

/// A robust Combine publisher for single model SQLiteORM subscriptions
/// Uses atomic setup to eliminate race conditions without complex state tracking
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@MainActor
public final class SingleQuerySubscription<T: ORMTable>: ObservableObject {
    @Published public private(set) var result: ORMResult<T?> = .success(nil)
    
    private let repository: Repository<T>
    private let query: ORMQueryBuilder<T>?
    private let modelId: T.IDType?
    private let changeNotifier: ChangeNotifier
    private var cancellable: AnyCancellable?
    
    /// Initialize subscription for a specific model ID
    /// - Parameters:
    ///   - repository: The repository to query
    ///   - id: The ID of the model to subscribe to
    ///   - changeNotifier: The change notification system
    public nonisolated init(repository: Repository<T>, id: T.IDType, changeNotifier: ChangeNotifier) {
        self.repository = repository
        self.modelId = id
        self.query = nil
        self.changeNotifier = changeNotifier
        
        Task { @MainActor in
            await self.atomicSetup()
        }
    }
    
    /// Initialize subscription for the first result of a query
    /// - Parameters:
    ///   - repository: The repository to query
    ///   - query: Query builder to find the first matching result
    ///   - changeNotifier: The change notification system
    public nonisolated init(repository: Repository<T>, query: ORMQueryBuilder<T>, changeNotifier: ChangeNotifier) {
        self.repository = repository
        self.query = query
        self.modelId = nil
        self.changeNotifier = changeNotifier
        
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
        let fetchResult: ORMResult<T?>
        
        if let id = modelId {
            // Find by specific ID
            fetchResult = await repository.find(id: id)
        } else if let query = query {
            // Find first matching query
            fetchResult = await repository.findFirst(query: query)
        } else {
            // This shouldn't happen, but handle gracefully
            fetchResult = .success(nil)
        }
        
        self.result = fetchResult
    }
    
    /// Manually refresh the subscription data
    public func refresh() async {
        await refreshData()
    }
    
    /// Convenience access to the model (nil if not found or error)
    public var model: T? {
        switch result {
        case .success(let model):
            return model
        case .failure:
            return nil
        }
    }
    
    /// Check if subscription has a model
    public var hasModel: Bool {
        return model != nil
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

