import Foundation
import SwiftSync

/// Example news article model
struct NewsArticle: ORMTable {
    var id: Int = 0
    var title: String
    var content: String
    var publishedAt: Date
    var category: String
    var viewCount: Int = 0
    
    // Sync properties
    var lastSyncTimestamp: Date?
    var isDirty: Bool = false
    var syncStatus: SyncStatus = .synced
    var serverID: String?
    
    static var tableName: String { "news_articles" }
    
    static var indexes: [ORMIndex] {
        [
            ORMIndex(name: "idx_published_at", columns: ["publishedAt"]),
            ORMIndex(name: "idx_category", columns: ["category"])
        ]
    }
}

/// Example demonstrating model limits for a news app
class ModelLimitExample {
    private let orm: ORM
    
    init() {
        // Create ORM with test database
        self.orm = createTestORM(filename: "news_app_example")
    }
    
    /// Setup the database and configure model limits
    func setup() async throws {
        // Open database and create tables
        let result = await orm.openAndCreateTables(NewsArticle.self)
        switch result {
        case .success:
            print("✅ Database setup completed successfully")
        case .failure(let error):
            print("❌ Database setup failed: \(error)")
            throw error
        }
        
        // Configure model limits for news articles
        await configureModelLimits()
    }
    
    /// Configure different model limit strategies
    private func configureModelLimits() async {
        print("\n📋 Configuring model limits...")
        
        // Configure removal callbacks
        await setupRemovalCallbacks()
        
        // Example 1: FIFO strategy - Keep only 100 most recent articles
        let fifoLimit = ModelLimit(
            maxCount: 100,
            removalStrategy: .fifo,
            enabled: true,
            batchSize: 10
        )
        
        await orm.setModelLimit(for: NewsArticle.self, limit: fifoLimit)
        print("✅ Configured FIFO limit: max 100 articles, remove 10 oldest when exceeded")
    }
    
    /// Setup removal callbacks to monitor limit enforcement
    private func setupRemovalCallbacks() async {
        // Global callback for all model types
        await orm.setGlobalModelRemovalCallback { removalInfo in
            print("🗑️ Global: Removed \(removalInfo.removedCount) items from \(removalInfo.tableName)")
            print("   Strategy: \(removalInfo.removalStrategy)")
            print("   Reason: \(removalInfo.reason)")
            print("   Time: \(removalInfo.removedAt)")
        }
        
        // Specific callback for NewsArticle
        await orm.setModelRemovalCallback(for: NewsArticle.self) { removalInfo in
            print("📰 NewsArticle specific: Removed \(removalInfo.removedCount) articles due to \(removalInfo.reason)")
            if removalInfo.reason == .limitExceeded {
                print("   💡 Consider increasing the limit or reviewing your cleanup strategy")
            }
        }
    }
    
    /// Demonstrate inserting articles and automatic limit enforcement
    func demonstrateAutoLimitEnforcement() async throws {
        print("\n🔄 Demonstrating automatic limit enforcement...")
        
        let repository = orm.repository(for: NewsArticle.self)
        
        // Insert 105 articles to trigger limit enforcement
        for i in 1...105 {
            var article = NewsArticle(
                title: "Breaking News #\(i)",
                content: "This is the content for news article number \(i). Lorem ipsum dolor sit amet...",
                publishedAt: Date().addingTimeInterval(TimeInterval(i * 60)), // 1 minute apart
                category: i % 2 == 0 ? "Technology" : "Sports"
            )
            
            let result = await repository.insert(&article)
            switch result {
            case .success(let insertedArticle):
                if i % 20 == 0 {
                    print("📰 Inserted article #\(i): \(insertedArticle.title)")
                }
            case .failure(let error):
                print("❌ Failed to insert article #\(i): \(error)")
                throw error
            }
        }
        
        // Check final count
        let countResult = await repository.count()
        switch countResult {
        case .success(let count):
            print("📊 Final article count: \(count) (should be 100 due to limit enforcement)")
        case .failure(let error):
            print("❌ Failed to get count: \(error)")
        }
    }
    
    /// Demonstrate different removal strategies
    func demonstrateDifferentStrategies() async throws {
        print("\n🔀 Demonstrating different removal strategies...")
        
        let repository = orm.repository(for: NewsArticle.self)
        
        // Clear existing data
        let deleteResult = await orm.execute("DELETE FROM news_articles")
        switch deleteResult {
        case .success:
            print("🗑️ Cleared existing articles")
        case .failure(let error):
            print("❌ Failed to clear articles: \(error)")
            throw error
        }
        
        // Test LRU strategy
        print("\n📖 Testing LRU (Least Recently Used) strategy...")
        let lruLimit = ModelLimit(maxCount: 5, removalStrategy: .lru, enabled: true)
        await repository.setModelLimit(lruLimit)
        
        // Insert 5 articles
        var articles: [NewsArticle] = []
        for i in 1...5 {
            var article = NewsArticle(
                title: "LRU Article #\(i)",
                content: "Content for LRU test article \(i)",
                publishedAt: Date().addingTimeInterval(TimeInterval(i * 60)),
                category: "Test"
            )
            
            let result = await repository.insert(&article)
            switch result {
            case .success(let insertedArticle):
                articles.append(insertedArticle)
                print("📰 Inserted: \(insertedArticle.title)")
            case .failure(let error):
                throw error
            }
        }
        
        // Access some articles to update their LRU status
        print("\n👀 Accessing articles 1, 3, and 5 to update LRU tracking...")
        for i in [0, 2, 4] { // Articles 1, 3, 5
            let result = await repository.find(id: articles[i].id)
            switch result {
            case .success(let article):
                if let article = article {
                    print("📖 Accessed: \(article.title)")
                }
            case .failure(let error):
                print("❌ Failed to access article: \(error)")
            }
        }
        
        // Insert one more article to trigger LRU removal
        print("\n➕ Inserting one more article to trigger LRU removal...")
        var newArticle = NewsArticle(
            title: "LRU Article #6",
            content: "This should trigger removal of least recently used article",
            publishedAt: Date().addingTimeInterval(TimeInterval(6 * 60)),
            category: "Test"
        )
        
        let insertResult = await repository.insert(&newArticle)
        switch insertResult {
        case .success(let article):
            print("📰 Inserted: \(article.title)")
        case .failure(let error):
            throw error
        }
        
        // Check which articles remain
        let remainingResult = await repository.findAll()
        switch remainingResult {
        case .success(let remaining):
            print("\n📊 Remaining articles after LRU enforcement:")
            for article in remaining.sorted(by: { $0.id < $1.id }) {
                print("  - \(article.title)")
            }
        case .failure(let error):
            print("❌ Failed to get remaining articles: \(error)")
        }
    }
    
    /// Demonstrate manual limit enforcement and statistics
    func demonstrateManualEnforcementAndStats() async throws {
        print("\n📊 Demonstrating manual enforcement and statistics...")
        
        let repository = orm.repository(for: NewsArticle.self)
        
        // Configure a small limit but disable automatic enforcement
        let manualLimit = ModelLimit(maxCount: 3, removalStrategy: .random, enabled: false)
        await repository.setModelLimit(manualLimit)
        
        // Clear and insert articles without automatic enforcement
        let deleteResult = await orm.execute("DELETE FROM news_articles")
        switch deleteResult {
        case .success:
            print("🗑️ Cleared existing articles")
        case .failure(let error):
            throw error
        }
        
        // Insert 6 articles (exceeding the limit)
        for i in 1...6 {
            var article = NewsArticle(
                title: "Manual Test Article #\(i)",
                content: "Content for manual test article \(i)",
                publishedAt: Date().addingTimeInterval(TimeInterval(i * 60)),
                category: "Manual Test"
            )
            
            let result = await repository.insert(&article)
            switch result {
            case .success(let insertedArticle):
                print("📰 Inserted: \(insertedArticle.title)")
            case .failure(let error):
                throw error
            }
        }
        
        // Get statistics before enforcement
        if let stats = await repository.getModelLimitStatistics() {
            print("\n📈 Statistics before manual enforcement:")
            print("  - Current count: \(stats.currentCount)")
            print("  - Max count: \(stats.maxCount)")
            print("  - Utilization: \(String(format: "%.1f", stats.utilizationPercentage))%")
            print("  - Approaching limit: \(stats.isApproachingLimit)")
            print("  - Exceeded limit: \(stats.hasExceededLimit)")
            print("  - Strategy: \(stats.removalStrategy)")
        }
        
        // Manually enforce limits
        print("\n🔧 Manually enforcing limits...")
        let enforceResult = await repository.enforceLimits(reason: .manualEnforcement)
        switch enforceResult {
        case .success:
            print("✅ Manual limit enforcement completed")
        case .failure(let error):
            print("❌ Manual limit enforcement failed: \(error)")
            throw error
        }
        
        // Get statistics after enforcement
        if let stats = await repository.getModelLimitStatistics() {
            print("\n📈 Statistics after manual enforcement:")
            print("  - Current count: \(stats.currentCount)")
            print("  - Max count: \(stats.maxCount)")
            print("  - Utilization: \(String(format: "%.1f", stats.utilizationPercentage))%")
            print("  - Approaching limit: \(stats.isApproachingLimit)")
            print("  - Exceeded limit: \(stats.hasExceededLimit)")
        }
        
        // Show remaining articles
        let remainingResult = await repository.findAll()
        switch remainingResult {
        case .success(let remaining):
            print("\n📊 Remaining articles after manual enforcement:")
            for article in remaining.sorted(by: { $0.id < $1.id }) {
                print("  - \(article.title)")
            }
        case .failure(let error):
            print("❌ Failed to get remaining articles: \(error)")
        }
    }
    
    /// Demonstrate Combine integration with model limits
    func demonstrateCombineIntegration() async throws {
        print("\n🔄 Demonstrating Combine integration with model limits...")
        
        let repository = orm.repository(for: NewsArticle.self)
        
        // Configure a small limit to trigger removals
        let smallLimit = ModelLimit(maxCount: 3, removalStrategy: .fifo, enabled: true)
        await repository.setModelLimit(smallLimit)
        
        // Clear existing data
        let deleteResult = await orm.execute("DELETE FROM news_articles")
        switch deleteResult {
        case .success:
            print("🗑️ Cleared existing articles")
        case .failure(let error):
            throw error
        }
        
        // Set up a repository-specific callback to demonstrate notifications
        await repository.setModelRemovalCallback { removalInfo in
            print("🔔 Repository callback: \(removalInfo.removedCount) articles removed")
            print("   This will trigger Combine subscribers to update!")
        }
        
        // Note: In a real app, you would set up Combine subscribers here like:
        // let subscription = await repository.subscribe()
        //     .sink { articles in
        //         print("Combine: Updated with \(articles.count) articles")
        //     }
        
        print("\n📝 Adding articles that will trigger limit enforcement...")
        for i in 1...5 {
            var article = NewsArticle(
                title: "Combine Test Article #\(i)",
                content: "This article will test Combine integration with limits",
                publishedAt: Date().addingTimeInterval(TimeInterval(i * 60)),
                category: "Combine Test"
            )
            
            let result = await repository.insert(&article)
            switch result {
            case .success(let insertedArticle):
                print("📰 Inserted: \(insertedArticle.title)")
                if i > 3 {
                    print("   ⚡ This should trigger removal callbacks and Combine notifications")
                }
            case .failure(let error):
                throw error
            }
        }
        
        let countResult = await repository.count()
        switch countResult {
        case .success(let count):
            print("📊 Final count: \(count) articles (should be 3 due to limit)")
        case .failure(let error):
            print("❌ Failed to get count: \(error)")
        }
    }
    
    /// Demonstrate global statistics and cleanup
    func demonstrateGlobalManagement() async throws {
        print("\n🌍 Demonstrating global model limit management...")
        
        // Get global statistics
        let globalStats = await orm.getModelLimitStatistics()
        print("\n📊 Global model limit statistics:")
        for (tableName, stats) in globalStats {
            print("  - \(tableName):")
            print("    Current: \(stats.currentCount)/\(stats.maxCount)")
            print("    Strategy: \(stats.removalStrategy)")
            print("    Enabled: \(stats.enabled)")
        }
        
        // Cleanup access tracking
        print("\n🧹 Cleaning up access tracking data...")
        await orm.cleanupAccessTracking(olderThan: 1) // Clean entries older than 1 second for demo
        print("✅ Access tracking cleanup completed")
        
        // Remove model limit
        print("\n🚫 Removing model limit configuration...")
        await orm.removeModelLimit(for: NewsArticle.self)
        
        let updatedStats = await orm.getModelLimitStatistics()
        if updatedStats.isEmpty {
            print("✅ Model limit configuration removed successfully")
        } else {
            print("⚠️ Some model limits still configured: \(updatedStats.keys)")
        }
    }
    
    /// Run the complete example
    func runExample() async throws {
        print("🚀 Starting Model Limit Example for News App")
        print("=" * 50)
        
        try await setup()
        try await demonstrateAutoLimitEnforcement()
        try await demonstrateDifferentStrategies()
        try await demonstrateManualEnforcementAndStats()
        try await demonstrateCombineIntegration()
        try await demonstrateGlobalManagement()
        
        print("\n" + "=" * 50)
        print("✅ Model Limit Example completed successfully!")
        print("\nKey features demonstrated:")
        print("  • Automatic limit enforcement on insert")
        print("  • Multiple removal strategies (FIFO, LRU, Random)")
        print("  • Access tracking for LRU/MRU strategies")
        print("  • Manual limit enforcement")
        print("  • Statistics and monitoring")
        print("  • Removal callbacks with reasons")
        print("  • Combine integration and notifications")
        print("  • Global management and cleanup")
    }
}

// Extension to repeat strings
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}

// Example usage
@main
struct ModelLimitExampleRunner {
    static func main() async {
        let example = ModelLimitExample()
        
        do {
            try await example.runExample()
        } catch {
            print("❌ Example failed with error: \(error)")
        }
    }
} 