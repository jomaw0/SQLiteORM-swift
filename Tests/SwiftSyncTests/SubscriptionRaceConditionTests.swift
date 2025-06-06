import Testing
import Foundation
@testable import SwiftSync
@preconcurrency import Combine

/// Test suite specifically for subscription race condition issues
/// These tests reproduce the race condition between subscription initialization and data creation
@Suite("Subscription Race Condition Tests")
struct SubscriptionRaceConditionTests {
    
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
    
    // MARK: - Race Condition Tests (These should FAIL before the fix)
    
    @Test("Race Condition - Subscription Before Data Creation (SHOULD FAIL BEFORE FIX)")
    func testRaceConditionSubscriptionBeforeData() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, repo) = await setupTestEnvironment()
        
        // Step 1: Create subscription BEFORE any data exists (mimicking problematic pattern)
        let subscription = repo.subscribe()
        
        // Step 2: Immediately create data (race condition scenario)
        var model = TestModel(name: "Test Model")
        let insertResult = await repo.insert(&model)
        #expect(insertResult.isSuccess, "Insert should succeed")
        
        // Step 3: Wait minimal time and check if subscription shows data
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // This test should FAIL before the fix because subscription might miss the data
        await MainActor.run {
            switch subscription.result {
            case .success(let models):
                #expect(models.count == 1, "Subscription should show the inserted data (FAILS due to race condition)")
                #expect(models.first?.name == "Test Model", "Should contain the correct model")
            case .failure(let error):
                Issue.record("Subscription should not fail: \(error)")
            }
        }
    }
    
    @Test("Race Condition - Filtered Subscription Before Data (SHOULD FAIL BEFORE FIX)")
    func testRaceConditionFilteredSubscriptionBeforeData() async throws {
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
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        // This test should FAIL before the fix due to timing issues with filtered queries
        await MainActor.run {
            switch subscription.result {
            case .success(let models):
                #expect(models.count == 1, "Filtered subscription should show matching data (FAILS due to race condition)")
                #expect(models.first?.isActive == true, "Should contain active model")
            case .failure(let error):
                Issue.record("Filtered subscription should not fail: \(error)")
            }
        }
    }
    
    @Test("Race Condition - Multiple Subscriptions Different Timing (SHOULD FAIL BEFORE FIX)")
    func testRaceConditionMultipleSubscriptionsTiming() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, repo) = await setupTestEnvironment()
        
        // Create multiple subscriptions at the same time (all before data exists)
        let allSubscription = repo.subscribe()
        let activeSubscription = repo.subscribe(
            query: ORMQueryBuilder<TestModel>().where("isActive", .equal, true)
        )
        let countSubscription = repo.subscribeCount()
        
        // Immediately insert data
        var model1 = TestModel(name: "Model 1", isActive: true)
        var model2 = TestModel(name: "Model 2", isActive: false)
        var model3 = TestModel(name: "Model 3", isActive: true)
        
        let result1 = await repo.insert(&model1)
        let result2 = await repo.insert(&model2)
        let result3 = await repo.insert(&model3)
        
        #expect(result1.isSuccess && result2.isSuccess && result3.isSuccess, "All inserts should succeed")
        
        // Wait for subscriptions to update
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // These assertions should FAIL before the fix due to race conditions
        await MainActor.run {
            // All models subscription
            if case .success(let allModels) = allSubscription.result {
                #expect(allModels.count == 3, "All subscription should show 3 models (FAILS due to race condition)")
            } else {
                Issue.record("All subscription should succeed")
            }
            
            // Active models subscription (filtered)
            if case .success(let activeModels) = activeSubscription.result {
                #expect(activeModels.count == 2, "Active subscription should show 2 models (FAILS due to race condition)")
                #expect(activeModels.allSatisfy { $0.isActive }, "All should be active")
            } else {
                Issue.record("Active subscription should succeed")
            }
            
            // Count subscription
            if case .success(let count) = countSubscription.result {
                #expect(count == 3, "Count subscription should show 3 (FAILS due to race condition)")
            } else {
                Issue.record("Count subscription should succeed")
            }
        }
    }
    
    @Test("Race Condition - Demo App Pattern Reproduction (SHOULD FAIL BEFORE FIX)")
    func testRaceConditionDemoAppPattern() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, repo) = await setupTestEnvironment()
        
        // Step 1: Mimic demo app DatabaseManager.setupSubscriptions() - subscriptions created first
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
        
        // Step 3: Wait for reactive update (this is where the race condition manifests)
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        // This assertion should FAIL before the fix - subscription shows empty even though data exists
        await MainActor.run {
            switch subscription.result {
            case .success(let models):
                #expect(models.count == 1, "Subscription should show the sample data (FAILS in demo app)")
                #expect(models.first?.name == "Sample Model", "Should contain the sample model")
            case .failure(let error):
                Issue.record("Subscription should not fail: \(error)")
            }
        }
        
        // Verify that the data actually exists in database (this should pass)
        let verifyResult = await repo.findAll()
        if case .success(let allModels) = verifyResult {
            #expect(allModels.count == 1, "Database should contain the data")
        }
    }
    
    @Test("Race Condition - Very Short Timing Window (SHOULD FAIL BEFORE FIX)")
    func testRaceConditionVeryShortTiming() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, repo) = await setupTestEnvironment()
        
        // Create subscription and immediately create data with no delay
        let subscription = repo.subscribe()
        
        // Insert data immediately (smallest possible race window)
        var model = TestModel(name: "Immediate Model")
        _ = await repo.insert(&model)
        
        // Check subscription result with minimal wait
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // This test should FAIL before the fix due to very short timing window
        await MainActor.run {
            switch subscription.result {
            case .success(let models):
                #expect(models.count == 1, "Should show immediate data (FAILS with very short timing)")
            case .failure(let error):
                Issue.record("Subscription should not fail: \(error)")
            }
        }
    }
    
    // MARK: - Control Tests (These should PASS both before and after the fix)
    
    @Test("Control Test - Data Created Before Subscription (SHOULD PASS)")
    func testControlDataBeforeSubscription() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, repo) = await setupTestEnvironment()
        
        // Step 1: Create data FIRST
        var model = TestModel(name: "Pre-existing Model")
        let insertResult = await repo.insert(&model)
        #expect(insertResult.isSuccess, "Insert should succeed")
        
        // Step 2: Create subscription AFTER data exists
        let subscription = repo.subscribe()
        
        // Step 3: Wait for subscription to load
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // This should PASS both before and after the fix
        await MainActor.run {
            switch subscription.result {
            case .success(let models):
                #expect(models.count == 1, "Should load pre-existing data")
                #expect(models.first?.name == "Pre-existing Model", "Should contain the correct model")
            case .failure(let error):
                Issue.record("Subscription should not fail: \(error)")
            }
        }
    }
    
    @Test("Control Test - Empty Database Subscription (SHOULD PASS)")
    func testControlEmptyDatabaseSubscription() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, repo) = await setupTestEnvironment()
        
        // Create subscription on empty database
        let subscription = repo.subscribe()
        
        // Wait for initial load
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Should show empty array (this should PASS both before and after the fix)
        await MainActor.run {
            switch subscription.result {
            case .success(let models):
                #expect(models.isEmpty, "Should start with empty array")
            case .failure(let error):
                Issue.record("Empty database subscription should not fail: \(error)")
            }
        }
    }
    
    @Test("Control Test - Reactive Updates After Proper Setup (SHOULD PASS)")
    func testControlReactiveUpdatesAfterSetup() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, repo) = await setupTestEnvironment()
        
        // Proper setup: create data first, then subscription
        var model = TestModel(name: "Initial Model")
        _ = await repo.insert(&model)
        
        let subscription = repo.subscribe()
        try await Task.sleep(nanoseconds: 100_000_000) // Wait for initial load
        
        // Now add more data - reactive updates should work
        var newModel = TestModel(name: "New Model")
        let insertResult = await repo.insert(&newModel)
        #expect(insertResult.isSuccess, "New insert should succeed")
        
        try await Task.sleep(nanoseconds: 150_000_000) // Wait for reactive update
        
        // This should PASS both before and after the fix
        await MainActor.run {
            switch subscription.result {
            case .success(let models):
                #expect(models.count == 2, "Should show both models after reactive update")
                let names = Set(models.map { $0.name })
                #expect(names.contains("Initial Model"), "Should contain initial model")
                #expect(names.contains("New Model"), "Should contain new model")
            case .failure(let error):
                Issue.record("Reactive update should not fail: \(error)")
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