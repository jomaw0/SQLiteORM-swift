import Testing
@testable import SwiftSync
import Foundation

/// Test model for limit removal testing
@ORMTable
struct TestArticle: ORMTable {
    typealias IDType = Int
    var id: Int = 0
    var title: String = ""
    var content: String = ""
    var createdAt: Date = Date()
    
    init() {}
    
    init(id: Int = 0, title: String, content: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
    }
}

@Suite("Model Limit Removal Tests")
struct ModelLimitRemovalTests {
    
    /// Helper to create a test environment
    func createTestEnvironment() async throws -> (ORM, Repository<TestArticle>) {
        let orm = createInMemoryORM()
        let openResult = await orm.open()
        
        switch openResult {
        case .success:
            break
        case .failure(let error):
            Issue.record("Failed to open database: \(error)")
            throw error
        }
        
        // Create table
        let result = await orm.createTables(TestArticle.self)
        
        switch result {
        case .success:
            break
        case .failure(let error):
            Issue.record("Failed to create table: \(error)")
            throw error
        }
        
        let repository = await orm.repository(for: TestArticle.self)
        return (orm, repository)
    }
    
    /// Helper to cleanup test environment
    func cleanupTestEnvironment(orm: ORM) async throws {
        _ = await orm.close()
    }
    
    // MARK: - Default Behavior Tests
    
    @Test("Model limits are disabled by default")
    func modelLimitIsDisabledByDefault() async throws {
        // Test that model limits are disabled by default
        let defaultLimit = ModelLimit(maxCount: 10)
        #expect(!defaultLimit.enabled, "Model limits should be disabled by default")
    }
    
    @Test("No enforcement when disabled")
    func noEnforcementWhenDisabled() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Set up a disabled limit
        let disabledLimit = ModelLimit(maxCount: 2, removalStrategy: .fifo, enabled: false)
        await repository.setModelLimit(disabledLimit)
        
        // Insert more articles than the limit
        for i in 1...5 {
            var article = TestArticle(title: "Article \(i)", content: "Content \(i)")
            _ = await repository.insert(&article)
        }
        
        // Verify no removal occurred
        let countResult = await repository.count()
        switch countResult {
        case .success(let count):
            #expect(count == 5, "No articles should be removed when limits are disabled")
        case .failure(let error):
            Issue.record("Failed to count articles: \(error)")
            throw error
        }
    }
    
    // MARK: - Basic Functionality Tests
    
    @Test("Model limit configuration works")
    func modelLimitConfiguration() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Test setting different limit configurations
        let fifoLimit = ModelLimit(maxCount: 3, removalStrategy: .fifo, enabled: true)
        await repository.setModelLimit(fifoLimit)
        
        let currentLimit = await repository.getModelLimit()
        #expect(currentLimit?.maxCount == 3)
        #expect(currentLimit?.removalStrategy == .fifo)
        #expect(currentLimit?.enabled == true)
        
        // Test changing configuration
        let lifoLimit = ModelLimit(maxCount: 5, removalStrategy: .lifo, enabled: false)
        await repository.setModelLimit(lifoLimit)
        
        let updatedLimit = await repository.getModelLimit()
        #expect(updatedLimit?.maxCount == 5)
        #expect(updatedLimit?.removalStrategy == .lifo)
        #expect(updatedLimit?.enabled == false)
    }
    
    @Test("Manual enforcement works")
    func manualEnforcement() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Set up enabled limit and insert excess articles
        let limit = ModelLimit(maxCount: 2, removalStrategy: .fifo, enabled: true)
        await repository.setModelLimit(limit)
        
        for i in 1...4 {
            var article = TestArticle(title: "Article \(i)", content: "Content \(i)")
            _ = await repository.insert(&article)
        }
        
        // With automatic enforcement enabled, we should already have 2 articles
        let finalCount = await repository.count()
        switch finalCount {
        case .success(let count):
            #expect(count <= 2, "Should have at most 2 articles due to automatic enforcement")
        case .failure(let error):
            Issue.record("Failed to count articles: \(error)")
            throw error
        }
        
        // Test manual enforcement method exists and works
        let enforcementResult = await repository.enforceLimits(reason: .manualEnforcement)
        switch enforcementResult {
        case .success:
            // Success - enforcement completed
            break
        case .failure(let error):
            Issue.record("Manual enforcement failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Removal Functionality Tests
    
    @Test("FIFO removal strategy removes oldest items first")
    func fifoRemovalStrategy() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Set up FIFO limit with max 3 items
        let limit = ModelLimit(maxCount: 3, removalStrategy: .fifo, enabled: true)
        await repository.setModelLimit(limit)
        
        // Insert 5 articles in order
        var insertedIds: [Int] = []
        for i in 1...5 {
            var article = TestArticle(title: "Article \(i)", content: "Content for article \(i)")
            let result = await repository.insert(&article)
            switch result {
            case .success:
                insertedIds.append(article.id)
            case .failure(let error):
                Issue.record("Failed to insert article \(i): \(error)")
                throw error
            }
        }
        
        // Should have exactly 3 articles (limit enforced)
        let countResult = await repository.count()
        switch countResult {
        case .success(let count):
            #expect(count == 3, "Should have exactly 3 articles after FIFO enforcement")
        case .failure(let error):
            Issue.record("Failed to count articles: \(error)")
            throw error
        }
        
        // Verify the remaining articles are the last 3 inserted (Article 3, 4, 5)
        let remainingResult = await repository.findAll()
        switch remainingResult {
        case .success(let articles):
            let titles = articles.map { $0.title }.sorted()
            #expect(titles.contains("Article 3"), "Article 3 should remain")
            #expect(titles.contains("Article 4"), "Article 4 should remain")
            #expect(titles.contains("Article 5"), "Article 5 should remain")
            #expect(!titles.contains("Article 1"), "Article 1 should be removed (oldest)")
            #expect(!titles.contains("Article 2"), "Article 2 should be removed (second oldest)")
        case .failure(let error):
            Issue.record("Failed to get remaining articles: \(error)")
            throw error
        }
    }
    
    @Test("LIFO removal strategy removes newest items first")
    func lifoRemovalStrategy() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Set up LIFO limit with max 3 items
        let limit = ModelLimit(maxCount: 3, removalStrategy: .lifo, enabled: true)
        await repository.setModelLimit(limit)
        
        // Insert 5 articles in order
        for i in 1...5 {
            var article = TestArticle(title: "Article \(i)", content: "Content for article \(i)")
            _ = await repository.insert(&article)
        }
        
        // Should have exactly 3 articles (limit enforced)
        let countResult = await repository.count()
        switch countResult {
        case .success(let count):
            #expect(count == 3, "Should have exactly 3 articles after LIFO enforcement")
        case .failure(let error):
            Issue.record("Failed to count articles: \(error)")
            throw error
        }
        
        // Verify the remaining articles are the first 3 inserted (Article 1, 2, 3)
        let remainingResult = await repository.findAll()
        switch remainingResult {
        case .success(let articles):
            let titles = articles.map { $0.title }.sorted()
            #expect(titles.contains("Article 1"), "Article 1 should remain")
            #expect(titles.contains("Article 2"), "Article 2 should remain")
            #expect(titles.contains("Article 3"), "Article 3 should remain")
            #expect(!titles.contains("Article 4"), "Article 4 should be removed (newest)")
            #expect(!titles.contains("Article 5"), "Article 5 should be removed (second newest)")
        case .failure(let error):
            Issue.record("Failed to get remaining articles: \(error)")
            throw error
        }
    }
    
    @Test("Random removal strategy maintains count limit")
    func randomRemovalStrategy() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Set up random limit with max 2 items
        let limit = ModelLimit(maxCount: 2, removalStrategy: .random, enabled: true)
        await repository.setModelLimit(limit)
        
        // Insert 4 articles
        for i in 1...4 {
            var article = TestArticle(title: "Article \(i)", content: "Content for article \(i)")
            _ = await repository.insert(&article)
        }
        
        // Should have exactly 2 articles (limit enforced)
        let countResult = await repository.count()
        switch countResult {
        case .success(let count):
            #expect(count == 2, "Should have exactly 2 articles after random removal enforcement")
        case .failure(let error):
            Issue.record("Failed to count articles: \(error)")
            throw error
        }
        
        // Verify we have 2 articles from the original 4 (can't predict which ones due to random)
        let remainingResult = await repository.findAll()
        switch remainingResult {
        case .success(let articles):
            #expect(articles.count == 2, "Should have exactly 2 articles remaining")
            // All remaining articles should be from our original set
            let validTitles = ["Article 1", "Article 2", "Article 3", "Article 4"]
            for article in articles {
                #expect(validTitles.contains(article.title), "Article title should be from original set")
            }
        case .failure(let error):
            Issue.record("Failed to get remaining articles: \(error)")
            throw error
        }
    }
    
    @Test("Automatic enforcement triggers on each insert")
    func automaticEnforcementOnInsert() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Set up strict limit with max 1 item
        let limit = ModelLimit(maxCount: 1, removalStrategy: .fifo, enabled: true)
        await repository.setModelLimit(limit)
        
        // Insert first article
        var article1 = TestArticle(title: "Article 1", content: "Content 1")
        _ = await repository.insert(&article1)
        
        // Verify we have 1 article
        let count1 = await repository.count()
        switch count1 {
        case .success(let count):
            #expect(count == 1, "Should have 1 article after first insert")
        case .failure(let error):
            Issue.record("Failed to count after first insert: \(error)")
            throw error
        }
        
        // Insert second article - should trigger removal of first
        var article2 = TestArticle(title: "Article 2", content: "Content 2")
        _ = await repository.insert(&article2)
        
        // Should still have exactly 1 article
        let count2 = await repository.count()
        switch count2 {
        case .success(let count):
            #expect(count == 1, "Should still have 1 article after second insert")
        case .failure(let error):
            Issue.record("Failed to count after second insert: \(error)")
            throw error
        }
        
        // Verify the remaining article is the second one (FIFO removed the first)
        let remainingResult = await repository.findAll()
        switch remainingResult {
        case .success(let articles):
            #expect(articles.count == 1, "Should have exactly 1 article")
            #expect(articles.first?.title == "Article 2", "Should have Article 2 remaining")
        case .failure(let error):
            Issue.record("Failed to get remaining articles: \(error)")
            throw error
        }
    }
    
    @Test("Batch removal works correctly")
    func batchRemovalFunctionality() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Set up limit with batch size of 2
        let limit = ModelLimit(maxCount: 3, removalStrategy: .fifo, enabled: true, batchSize: 2)
        await repository.setModelLimit(limit)
        
        // Insert many articles at once to test batch removal
        for i in 1...7 {
            var article = TestArticle(title: "Article \(i)", content: "Content for article \(i)")
            _ = await repository.insert(&article)
        }
        
        // Should have exactly 3 articles (limit enforced)
        let countResult = await repository.count()
        switch countResult {
        case .success(let count):
            #expect(count == 3, "Should have exactly 3 articles after batch removal")
        case .failure(let error):
            Issue.record("Failed to count articles: \(error)")
            throw error
        }
        
        // Verify the remaining articles are the last 3 (Article 5, 6, 7)
        let remainingResult = await repository.findAll()
        switch remainingResult {
        case .success(let articles):
            let titles = articles.map { $0.title }.sorted()
            #expect(titles.contains("Article 5"), "Article 5 should remain")
            #expect(titles.contains("Article 6"), "Article 6 should remain") 
            #expect(titles.contains("Article 7"), "Article 7 should remain")
        case .failure(let error):
            Issue.record("Failed to get remaining articles: \(error)")
            throw error
        }
    }
    
    @Test("No removal when disabled even with excess items")
    func noRemovalWhenDisabledWithExcess() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Set up disabled limit
        let limit = ModelLimit(maxCount: 2, removalStrategy: .fifo, enabled: false)
        await repository.setModelLimit(limit)
        
        // Insert way more articles than the limit
        for i in 1...6 {
            var article = TestArticle(title: "Article \(i)", content: "Content for article \(i)")
            _ = await repository.insert(&article)
        }
        
        // Should have all 6 articles (no enforcement)
        let countResult = await repository.count()
        switch countResult {
        case .success(let count):
            #expect(count == 6, "Should have all 6 articles when enforcement is disabled")
        case .failure(let error):
            Issue.record("Failed to count articles: \(error)")
            throw error
        }
        
        // Verify all articles are present
        let allResult = await repository.findAll()
        switch allResult {
        case .success(let articles):
            let titles = articles.map { $0.title }.sorted()
            for i in 1...6 {
                #expect(titles.contains("Article \(i)"), "Article \(i) should be present")
            }
        case .failure(let error):
            Issue.record("Failed to get all articles: \(error)")
            throw error
        }
    }
    
    @Test("Different strategies produce different results")
    func differentStrategiesProduceDifferentResults() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Test FIFO first
        let fifoLimit = ModelLimit(maxCount: 2, removalStrategy: .fifo, enabled: true)
        await repository.setModelLimit(fifoLimit)
        
        // Insert 3 articles for FIFO test
        for i in 1...3 {
            var article = TestArticle(title: "FIFO Article \(i)", content: "FIFO Content \(i)")
            _ = await repository.insert(&article)
        }
        
        let fifoResult = await repository.findAll()
        var fifoTitles: [String] = []
        switch fifoResult {
        case .success(let articles):
            fifoTitles = articles.map { $0.title }.sorted()
            #expect(articles.count == 2, "FIFO should have 2 articles")
        case .failure(let error):
            Issue.record("Failed to get FIFO articles: \(error)")
            throw error
        }
        
        // Clear and test LIFO - delete all existing articles
        let deleteResult = await repository.findAll()
        switch deleteResult {
        case .success(let existingArticles):
            for article in existingArticles {
                _ = await repository.delete(id: article.id)
            }
        case .failure(let error):
            Issue.record("Failed to get articles for deletion: \(error)")
            throw error
        }
        
        let lifoLimit = ModelLimit(maxCount: 2, removalStrategy: .lifo, enabled: true)
        await repository.setModelLimit(lifoLimit)
        
        // Insert 3 articles for LIFO test
        for i in 1...3 {
            var article = TestArticle(title: "LIFO Article \(i)", content: "LIFO Content \(i)")
            _ = await repository.insert(&article)
        }
        
        let lifoResult = await repository.findAll()
        switch lifoResult {
        case .success(let articles):
            let lifoTitles = articles.map { $0.title }.sorted()
            #expect(articles.count == 2, "LIFO should have 2 articles")
            
            // FIFO and LIFO should produce different results
            #expect(fifoTitles != lifoTitles, "FIFO and LIFO should produce different remaining articles")
        case .failure(let error):
            Issue.record("Failed to get LIFO articles: \(error)")
            throw error
        }
    }
    
    @Test("LRU strategy can be configured and enforces limits")
    func lruRemovalStrategy() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Set up LRU limit with max 2 items
        let limit = ModelLimit(maxCount: 2, removalStrategy: .lru, enabled: true)
        await repository.setModelLimit(limit)
        
        // Insert 3 articles to test limit enforcement
        for i in 1...3 {
            var article = TestArticle(title: "LRU Article \(i)", content: "Content \(i)")
            _ = await repository.insert(&article)
        }
        
        // Should have exactly 2 articles (limit enforced)
        let countResult = await repository.count()
        switch countResult {
        case .success(let count):
            #expect(count == 2, "Should have exactly 2 articles after LRU enforcement")
        case .failure(let error):
            Issue.record("Failed to count articles: \(error)")
            throw error
        }
        
        // Verify we have 2 articles remaining (exact articles depend on LRU implementation)
        let remainingResult = await repository.findAll()
        switch remainingResult {
        case .success(let articles):
            #expect(articles.count == 2, "Should have exactly 2 articles remaining")
            // All remaining articles should be from our original set
            let validTitles = ["LRU Article 1", "LRU Article 2", "LRU Article 3"]
            for article in articles {
                #expect(validTitles.contains(article.title), "Article title should be from original set")
            }
        case .failure(let error):
            Issue.record("Failed to get remaining articles: \(error)")
            throw error
        }
    }
    
    @Test("Size-based removal strategies work correctly")
    func sizeBasedRemovalStrategies() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Test smallest first strategy
        let smallestLimit = ModelLimit(maxCount: 2, removalStrategy: .smallestFirst, enabled: true)
        await repository.setModelLimit(smallestLimit)
        
        // Insert articles with different content sizes
        var smallArticle = TestArticle(title: "Small", content: "Short")
        var mediumArticle = TestArticle(title: "Medium", content: "Medium length content here")
        var largeArticle = TestArticle(title: "Large", content: "This is a much longer piece of content that should be considered large")
        
        _ = await repository.insert(&smallArticle)
        _ = await repository.insert(&mediumArticle)
        _ = await repository.insert(&largeArticle)
        
        // Should have exactly 2 articles (limit enforced)
        let countResult = await repository.count()
        switch countResult {
        case .success(let count):
            #expect(count == 2, "Should have exactly 2 articles after smallest-first enforcement")
        case .failure(let error):
            Issue.record("Failed to count articles: \(error)")
            throw error
        }
        
        // Verify the smallest article was removed first
        let remainingResult = await repository.findAll()
        switch remainingResult {
        case .success(let articles):
            let titles = articles.map { $0.title }.sorted()
            #expect(!titles.contains("Small"), "Small article should be removed first")
            #expect(titles.contains("Medium") || titles.contains("Large"), "Medium or Large articles should remain")
        case .failure(let error):
            Issue.record("Failed to get remaining articles: \(error)")
            throw error
        }
    }
    
    @Test("Statistics tracking works")
    func statisticsTracking() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Set up limit
        let limit = ModelLimit(maxCount: 3, removalStrategy: .fifo, enabled: true)
        await repository.setModelLimit(limit)
        
        // Insert some articles
        for i in 1...2 {
            var article = TestArticle(title: "Article \(i)", content: "Content \(i)")
            _ = await repository.insert(&article)
        }
        
        // Get statistics
        let stats = await repository.getModelLimitStatistics()
        #expect(stats?.currentCount == 2)
        #expect(stats?.maxCount == 3)
        #expect(stats?.utilizationPercentage ?? 0.0 < 100.0)
        #expect(stats?.utilizationPercentage ?? 0.0 > 0.0)
    }
    
    @Test("Different removal strategies can be configured")
    func removalStrategies() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Test all removal strategies can be set
        let strategies: [ModelRemovalStrategy] = [.fifo, .lifo, .lru, .mru, .random, .smallestFirst, .largestFirst]
        
        for strategy in strategies {
            let limit = ModelLimit(maxCount: 5, removalStrategy: strategy, enabled: false)
            await repository.setModelLimit(limit)
            
            let currentLimit = await repository.getModelLimit()
            #expect(currentLimit?.removalStrategy == strategy, "Strategy \(strategy) should be set correctly")
        }
    }
    
    @Test("Global limit management works")
    func globalLimitManagement() async throws {
        let (orm, _) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Test global enforcement
        let enforcementResult = await orm.manuallyEnforceLimits(for: TestArticle.self, reason: .cleanup)
        switch enforcementResult {
        case .success:
            // Success - no articles to remove yet
            break
        case .failure(let error):
            Issue.record("Global enforcement failed: \(error)")
            throw error
        }
        
        // Test passes if global enforcement works
        #expect(Bool(true), "Global enforcement should work without errors")
    }
    
    @Test("Callback configuration works")
    func callbackConfiguration() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Set up callback
        await repository.setModelRemovalCallback { removalInfo in
            // Callback logic
        }
        
        // Set up global callback
        await orm.setGlobalModelRemovalCallback { removalInfo in
            // Global callback
        }
        
        // Remove callbacks
        await repository.setModelRemovalCallback(nil)
        await orm.setGlobalModelRemovalCallback(nil)
        
        // Test passes if no errors occur
        #expect(Bool(true), "Callback configuration should work without errors")
    }
    
    @Test("Batch size configuration works")
    func batchSizeConfiguration() async throws {
        let (orm, repository) = try await createTestEnvironment()
        defer { Task { try await cleanupTestEnvironment(orm: orm) } }
        
        // Test different batch sizes
        let batchSizes = [1, 5, 10, 50]
        
        for batchSize in batchSizes {
            let limit = ModelLimit(maxCount: 20, removalStrategy: .fifo, enabled: false, batchSize: batchSize)
            await repository.setModelLimit(limit)
            
            let currentLimit = await repository.getModelLimit()
            #expect(currentLimit?.batchSize == batchSize, "Batch size \(batchSize) should be set correctly")
        }
    }
} 