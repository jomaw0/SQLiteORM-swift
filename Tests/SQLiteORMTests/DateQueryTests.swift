import Foundation
import Testing
@testable import SQLiteORM

@Suite("Date Query Convenience Methods Tests")
struct DateQueryTests {
    
    private func setupDatabase() async -> ORM {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil, "Database should open successfully")
        
        let createResult = await orm.createTables(for: [Event.self])
        #expect(createResult.toOptional() != nil, "Tables should be created successfully")
        
        return orm
    }
    
    private func createTestEvents(in repo: Repository<Event>) async -> [Event] {
        let calendar = Calendar.current
        let now = Date()
        
        // Create events with various dates
        var events: [Event] = []
        
        // Today
        var todayEvent = Event(title: "Today Event", eventDate: now)
        _ = await repo.insert(&todayEvent)
        events.append(todayEvent)
        
        // Yesterday
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        var yesterdayEvent = Event(title: "Yesterday Event", eventDate: yesterday)
        _ = await repo.insert(&yesterdayEvent)
        events.append(yesterdayEvent)
        
        // Tomorrow
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        var tomorrowEvent = Event(title: "Tomorrow Event", eventDate: tomorrow)
        _ = await repo.insert(&tomorrowEvent)
        events.append(tomorrowEvent)
        
        // Last week
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        var lastWeekEvent = Event(title: "Last Week Event", eventDate: lastWeek)
        _ = await repo.insert(&lastWeekEvent)
        events.append(lastWeekEvent)
        
        // Next week
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now)!
        var nextWeekEvent = Event(title: "Next Week Event", eventDate: nextWeek)
        _ = await repo.insert(&nextWeekEvent)
        events.append(nextWeekEvent)
        
        // Last month
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
        var lastMonthEvent = Event(title: "Last Month Event", eventDate: lastMonth)
        _ = await repo.insert(&lastMonthEvent)
        events.append(lastMonthEvent)
        
        // Last year
        let lastYear = calendar.date(byAdding: .year, value: -1, to: now)!
        var lastYearEvent = Event(title: "Last Year Event", eventDate: lastYear)
        _ = await repo.insert(&lastYearEvent)
        events.append(lastYearEvent)
        
        return events
    }
    
    @Test("whereBefore and whereAfter methods work correctly")
    func testBeforeAfterQueries() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: Event.self)
        _ = await createTestEvents(in: repo)
        
        let cutoffDate = Date()
        
        // Test before
        let beforeResults = await repo.query()
            .whereBefore("eventDate", date: cutoffDate)
            .findAll()
        
        if case .success(let events) = beforeResults {
            #expect(events.count > 0, "Should find events before cutoff date")
            #expect(events.allSatisfy { $0.eventDate < cutoffDate }, "All events should be before cutoff date")
        } else {
            Issue.record("Before query failed")
        }
        
        // Test after  
        let afterResults = await repo.query()
            .whereAfter("eventDate", date: cutoffDate)
            .findAll()
        
        if case .success(let events) = afterResults {
            #expect(events.allSatisfy { $0.eventDate > cutoffDate }, "All events should be after cutoff date")
        } else {
            Issue.record("After query failed")
        }
    }
    
    @Test("whereOnDate method works correctly")
    func testOnDateQuery() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: Event.self)
        _ = await createTestEvents(in: repo)
        
        // Test today
        let todayResults = await repo.query()
            .whereToday("eventDate")
            .findAll()
        
        if case .success(let events) = todayResults {
            #expect(events.count == 1, "Should find exactly one event today")
            #expect(events.first?.title == "Today Event", "Should find the today event")
        } else {
            Issue.record("Today query failed")
        }
        
        // Test yesterday
        let yesterdayResults = await repo.query()
            .whereYesterday("eventDate")
            .findAll()
        
        if case .success(let events) = yesterdayResults {
            #expect(events.count == 1, "Should find exactly one event yesterday")
            #expect(events.first?.title == "Yesterday Event", "Should find the yesterday event")
        } else {
            Issue.record("Yesterday query failed")
        }
    }
    
    @Test("whereWithinDateRange method works correctly")
    func testDateRangeQuery() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: Event.self)
        _ = await createTestEvents(in: repo)
        
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        
        // Test date range including yesterday, today, and tomorrow
        let rangeResults = await repo.query()
            .whereWithinDateRange("eventDate", from: yesterday, to: tomorrow)
            .findAll()
        
        if case .success(let events) = rangeResults {
            #expect(events.count == 3, "Should find exactly 3 events in the range")
            let titles = events.map { $0.title }
            #expect(titles.contains("Yesterday Event"), "Should include yesterday event")
            #expect(titles.contains("Today Event"), "Should include today event")
            #expect(titles.contains("Tomorrow Event"), "Should include tomorrow event")
        } else {
            Issue.record("Date range query failed")
        }
    }
    
    @Test("whereThisWeek method works correctly")
    func testThisWeekQuery() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: Event.self)
        _ = await createTestEvents(in: repo)
        
        let thisWeekResults = await repo.query()
            .whereThisWeek("eventDate")
            .findAll()
        
        if case .success(let events) = thisWeekResults {
            // Should find events from this week (today, yesterday if in same week, tomorrow if in same week)
            #expect(events.count >= 1, "Should find at least one event this week")
            let titles = events.map { $0.title }
            #expect(titles.contains("Today Event"), "Should include today event")
        } else {
            Issue.record("This week query failed")
        }
    }
    
    @Test("whereLastDays method works correctly")
    func testLastDaysQuery() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: Event.self)
        _ = await createTestEvents(in: repo)
        
        // Test last 7 days
        let last7DaysResults = await repo.query()
            .whereLastDays("eventDate", 7)
            .findAll()
        
        if case .success(let events) = last7DaysResults {
            #expect(events.count >= 2, "Should find at least 2 events in last 7 days")
            let titles = events.map { $0.title }
            #expect(titles.contains("Today Event"), "Should include today event")
            #expect(titles.contains("Yesterday Event"), "Should include yesterday event")
        } else {
            Issue.record("Last 7 days query failed")
        }
        
        // Test last 1 day
        let last1DayResults = await repo.query()
            .whereLastDays("eventDate", 1)
            .findAll()
        
        if case .success(let events) = last1DayResults {
            #expect(events.count >= 1, "Should find at least 1 event in last 1 day")
            let titles = events.map { $0.title }
            #expect(titles.contains("Today Event"), "Should include today event")
        } else {
            Issue.record("Last 1 day query failed")
        }
    }
    
    @Test("whereYear and whereMonth methods work correctly")
    func testYearMonthQueries() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: Event.self)
        _ = await createTestEvents(in: repo)
        
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        
        // Test current year
        let thisYearResults = await repo.query()
            .whereYear("eventDate", currentYear)
            .findAll()
        
        if case .success(let events) = thisYearResults {
            #expect(events.count >= 1, "Should find events from this year")
            let titles = events.map { $0.title }
            #expect(titles.contains("Today Event"), "Should include today event")
        } else {
            Issue.record("This year query failed")
        }
        
        // Test current month
        let thisMonthResults = await repo.query()
            .whereMonth("eventDate", currentMonth)
            .findAll()
        
        if case .success(let events) = thisMonthResults {
            #expect(events.count >= 1, "Should find events from this month")
            let titles = events.map { $0.title }
            #expect(titles.contains("Today Event"), "Should include today event")
        } else {
            Issue.record("This month query failed")
        }
    }
    
    @Test("whereLastHours and whereLastMinutes methods work correctly")
    func testTimeBasedQueries() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: Event.self)
        
        // Create events with precise timing
        let now = Date()
        
        // Event from 30 minutes ago
        let thirtyMinutesAgo = Calendar.current.date(byAdding: .minute, value: -30, to: now)!
        var recentEvent = Event(title: "Recent Event", eventDate: thirtyMinutesAgo)
        _ = await repo.insert(&recentEvent)
        
        // Event from 2 hours ago
        let twoHoursAgo = Calendar.current.date(byAdding: .hour, value: -2, to: now)!
        var olderEvent = Event(title: "Older Event", eventDate: twoHoursAgo)
        _ = await repo.insert(&olderEvent)
        
        // Event from 10 days ago (should not be in recent queries)
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: now)!
        var veryOldEvent = Event(title: "Very Old Event", eventDate: tenDaysAgo)
        _ = await repo.insert(&veryOldEvent)
        
        // Test last 1 hour
        let lastHourResults = await repo.query()
            .whereLastHours("eventDate", 1)
            .findAll()
        
        if case .success(let events) = lastHourResults {
            #expect(events.count == 1, "Should find exactly 1 event in last hour")
            #expect(events.first?.title == "Recent Event", "Should find the recent event")
        } else {
            Issue.record("Last hour query failed")
        }
        
        // Test last 3 hours
        let lastThreeHoursResults = await repo.query()
            .whereLastHours("eventDate", 3)
            .findAll()
        
        if case .success(let events) = lastThreeHoursResults {
            #expect(events.count == 2, "Should find exactly 2 events in last 3 hours")
            let titles = events.map { $0.title }
            #expect(titles.contains("Recent Event"), "Should include recent event")
            #expect(titles.contains("Older Event"), "Should include older event")
        } else {
            Issue.record("Last 3 hours query failed")
        }
        
        // Test last 45 minutes
        let lastFortyFiveMinutesResults = await repo.query()
            .whereLastMinutes("eventDate", 45)
            .findAll()
        
        if case .success(let events) = lastFortyFiveMinutesResults {
            #expect(events.count == 1, "Should find exactly 1 event in last 45 minutes")
            #expect(events.first?.title == "Recent Event", "Should find the recent event")
        } else {
            Issue.record("Last 45 minutes query failed")
        }
    }
    
    @Test("Chained date queries work correctly")
    func testChainedDateQueries() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: Event.self)
        
        // Create events with specific dates
        let calendar = Calendar.current
        let now = Date()
        
        // Event from 2 days ago
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        var event1 = Event(title: "Event 2 Days Ago", eventDate: twoDaysAgo)
        _ = await repo.insert(&event1)
        
        // Event from 5 days ago
        let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: now)!
        var event2 = Event(title: "Event 5 Days Ago", eventDate: fiveDaysAgo)
        _ = await repo.insert(&event2)
        
        // Event from 10 days ago
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: now)!
        var event3 = Event(title: "Event 10 Days Ago", eventDate: tenDaysAgo)
        _ = await repo.insert(&event3)
        
        // Test chained query: events from last 7 days, ordered by newest first
        let chainedResults = await repo.query()
            .whereLastDays("eventDate", 7)
            .newestFirst("eventDate")
            .findAll()
        
        if case .success(let events) = chainedResults {
            #expect(events.count == 2, "Should find exactly 2 events in last 7 days")
            #expect(events.first?.title == "Event 2 Days Ago", "First event should be most recent")
            #expect(events.last?.title == "Event 5 Days Ago", "Last event should be oldest in range")
        } else {
            Issue.record("Chained date query failed")
        }
        
        // Test subscription with date query
        let dateSubscription = await repo.query()
            .whereLastDays("eventDate", 7)
            .subscribeQuery()
        
        // Give subscription time to load
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        await MainActor.run {
            switch dateSubscription.result {
            case .success(let events):
                #expect(events.count == 2, "Subscription should find 2 events in last 7 days")
            case .failure(let error):
                Issue.record("Date subscription failed: \(error)")
            }
        }
    }
}

// Helper model for testing date queries
struct Event: ORMTable {
    typealias IDType = Int
    var id: Int = 0
    var title: String
    var eventDate: Date
    
    static let tableName = "events"
}