import Testing
import Foundation
@testable import SwiftSync
@preconcurrency import Combine

/// Test suite specifically for verifying the subscription race condition fix
/// These tests should PASS after implementing the awaitable subscription initialization
@Suite("Subscription Race Condition Fix Tests")
struct SubscriptionRaceConditionFixTests {
    
    // MARK: - Test Models
    
    @ORMTable
    struct TestModel: ORMTable {
        typealias IDType = Int
        var id: Int = 0
        var name: String
        var isActive: Bool = true
        var createdAt: Date = Date()
    }
    
    // MARK: - Helper Functions
    
    private func setupTestEnvironment() async -> (ORM, Repository<TestModel>) {
        let orm = createInMemoryORM()
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        
        let createResult = await orm.repository(for: TestModel.self).createTable()
        #expect(createResult.isSuccess, "Table should be created successfully")
        
        let repo = await orm.repository(for: TestModel.self)
        return (orm, repo)
    }
    
    // MARK: - Fix Verification Tests (These should PASS after the fix)
    
    @Test("Fixed - Subscription Before Data Creation")
    func testFixedSubscriptionBeforeDataCreation() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, repo) = await setupTestEnvironment()
        
        // Step 1: Create subscription BEFORE any data exists
        let subscription = repo.subscribe()
        
        // Step 2: Immediately create data
        var model = TestModel(name: "Test Model")
        let insertResult = await repo.insert(&model)
        #expect(insertResult.isSuccess, "Insert should succeed")
        
        // Step 3: Wait minimal time and check if subscription shows data
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // This test should PASS after the fix - subscription should show the data
        await MainActor.run {
            switch subscription.result {
            case .success(let models):
                #expect(models.count == 1, "Subscription should show the inserted data (FIXED)")
                #expect(models.first?.name == "Test Model", "Should contain the correct model")
            case .failure(let error):
                Issue.record("Subscription should not fail: \(error)")
            }
        }
    }
    
    @Test("Fixed - Filtered Subscription Before Data")
    func testFixedFilteredSubscriptionBeforeData() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, repo) = await setupTestEnvironment()
        
        // Step 1: Create filtered subscription BEFORE any data exists
        let query = ORMQueryBuilder<TestModel>().where("isActive", .equal, true)
        let subscription = repo.subscribe(query: query)
        
        // Step 2: Immediately create data that matches the filter
        var model = TestModel(name: "Active Model", isActive: true)
        let insertResult = await repo.insert(&model)
        #expect(insertResult.isSuccess, "Insert should succeed")
        
        // Step 3: Wait and check if filtered subscription shows data
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // This test should PASS after the fix - filtered subscription should show matching data
        await MainActor.run {
            switch subscription.result {
            case .success(let models):
                #expect(models.count == 1, "Filtered subscription should show matching data (FIXED)")
                #expect(models.first?.isActive == true, "Should contain active model")
            case .failure(let error):
                Issue.record("Filtered subscription should not fail: \(error)")
            }
        }
    }
    
    @Test("Fixed - Demo App Pattern")
    func testFixedDemoAppPattern() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, repo) = await setupTestEnvironment()
        
        // Step 1: Mimic demo app DatabaseManager.setupSubscriptions() - atomic setup works immediately
        let subscription = repo.subscribe(
            query: ORMQueryBuilder<TestModel>()
                .where("isActive", .equal, true)
                .orderBy("createdAt", ascending: false)
        )
        
        // Step 2: Mimic demo app DatabaseManager.loadInitialData() - data created after subscriptions
        
        // Check if database is empty (similar to hasExistingData check)
        let allDataResult = await repo.findAll()
        let hasExistingData = switch allDataResult {
        case .success(let models): !models.isEmpty
        case .failure: false
        }
        
        #expect(hasExistingData == false, "Database should be empty initially")
        
        // Create sample data (similar to createSampleData)
        var sampleModel = TestModel(name: "Sample Model")
        let createResult = await repo.insert(&sampleModel)
        #expect(createResult.isSuccess, "Sample model should be created")
        
        // Step 3: Wait for reactive update
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // This assertion should PASS after the fix - subscription shows data
        await MainActor.run {
            switch subscription.result {
            case .success(let models):
                #expect(models.count == 1, "Subscription should show the sample data (FIXED)")
                #expect(models.first?.name == "Sample Model", "Should contain the sample model")
            case .failure(let error):
                Issue.record("Subscription should not fail: \(error)")
            }
        }
    }
    
    @Test("Fixed - Multiple Subscriptions Different Timing")
    func testFixedMultipleSubscriptionsTiming() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, repo) = await setupTestEnvironment()
        
        // Create multiple subscriptions at the same time (all before data exists) - atomic setup
        let allSubscription = repo.subscribe()
        let activeSubscription = repo.subscribe(
            query: ORMQueryBuilder<TestModel>().where("isActive", .equal, true)
        )
        let countSubscription = repo.subscribeCount()
        
        // Insert data with small delays to ensure proper processing
        var model1 = TestModel(name: "Model 1", isActive: true)
        var model2 = TestModel(name: "Model 2", isActive: false)
        var model3 = TestModel(name: "Model 3", isActive: true)
        
        let result1 = await repo.insert(&model1)
        #expect(result1.isSuccess, "First insert should succeed")
        
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
        
        let result2 = await repo.insert(&model2)
        #expect(result2.isSuccess, "Second insert should succeed")
        
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
        
        let result3 = await repo.insert(&model3)
        #expect(result3.isSuccess, "Third insert should succeed")
        
        // Wait for subscriptions to update
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms - longer wait to ensure updates
        
        // These assertions should PASS after the fix
        await MainActor.run {
            // All models subscription
            if case .success(let allModels) = allSubscription.result {
                #expect(allModels.count == 3, "All subscription should show 3 models (FIXED)")
            } else {
                Issue.record("All subscription should succeed")
            }
            
            // Active models subscription (filtered)
            if case .success(let activeModels) = activeSubscription.result {
                #expect(activeModels.count == 2, "Active subscription should show 2 models (FIXED)")
                #expect(activeModels.allSatisfy { $0.isActive }, "All should be active")
            } else {
                Issue.record("Active subscription should succeed")
            }
            
            // Count subscription
            if case .success(let count) = countSubscription.result {
                #expect(count == 3, "Count subscription should show 3 (FIXED)")
            } else {
                Issue.record("Count subscription should succeed")
            }
        }
    }
}

// MARK: - Test Utilities

private extension ORMResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}