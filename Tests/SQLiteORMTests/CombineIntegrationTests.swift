import Testing
import Foundation
@testable import SQLiteORM

struct CombineIntegrationTests {
    
    @Test("Combine subscriptions can be created")
    func testSubscriptionCreation() async throws {
        // Only test on supported platforms
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        // Test that subscriptions can be created without crashing
        let allUsersSubscription = await userRepo.subscribe()
        let countSubscription = await userRepo.subscribeCount()
        
        // Basic verification that they are the correct types
        #expect(type(of: allUsersSubscription) == SimpleQuerySubscription<User>.self)
        #expect(type(of: countSubscription) == SimpleCountSubscription<User>.self)
        
        _ = await orm.close()
    }
    
    @Test("Change notifier basic functionality")
    func testChangeNotifier() async throws {
        // Only test on supported platforms
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let changeNotifier = ChangeNotifier()
        
        // Test notification (basic smoke test)
        await changeNotifier.notifyChange(for: "test_table")
        
        // Test cleanup
        await changeNotifier.cleanup(for: "test_table")
        await changeNotifier.cleanupAll()
        
        // If we get here without crashing, the basic functionality works
        #expect(true)
    }
}