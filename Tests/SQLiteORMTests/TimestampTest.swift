import Foundation
import Testing
@testable import SQLiteORM

@Suite("Timestamp Analysis")
struct TimestampAnalysisTests {
    
    @Test("Check current timestamp values")
    func testCurrentTimestamp() async throws {
        let now = Date()
        print("Current date: \(now)")
        print("Current timestamp: \(now.timeIntervalSince1970)")
        
        // Check if the timestamp is reasonable (should be around 1.7+ billion for 2025)
        let expectedMinTimestamp: TimeInterval = 1640995200 // Jan 1, 2022
        let expectedMaxTimestamp: TimeInterval = 1893456000 // Jan 1, 2030
        
        #expect(now.timeIntervalSince1970 > expectedMinTimestamp)
        #expect(now.timeIntervalSince1970 < expectedMaxTimestamp)
        
        // Check what happens with a 1994 date
        let calendar = Calendar.current
        let components = DateComponents(year: 1994, month: 1, day: 1)
        if let date1994 = calendar.date(from: components) {
            print("1994 date: \(date1994)")
            print("1994 timestamp: \(date1994.timeIntervalSince1970)")
            
            // Check if somehow timestamps are being interpreted as seconds since Jan 1, 1994
            let secondsSince1994 = now.timeIntervalSince(date1994)
            print("Seconds since 1994: \(secondsSince1994)")
            
            // Check if the issue might be with timeIntervalSinceReferenceDate
            print("timeIntervalSinceReferenceDate: \(now.timeIntervalSinceReferenceDate)")
            
            // Reference date is Jan 1, 2001
            let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
            print("Reference date (2001): \(referenceDate)")
        }
    }
    
    @Test("Check database date conversion edge cases")
    func testDatabaseDateConversion() async throws {
        // Test various timestamp interpretations
        let testTimestamps: [TimeInterval] = [
            0, // Unix epoch (1970)
            757382400, // Jan 1, 1994 00:00:00 UTC
            978307200, // Jan 1, 2001 00:00:00 UTC (NSDate reference)
            Date().timeIntervalSince1970 // Current time
        ]
        
        for timestamp in testTimestamps {
            let date = Date(timeIntervalSince1970: timestamp)
            print("Timestamp \(timestamp) -> Date: \(date)")
            
            // Convert to SQLite and back
            let sqliteValue = date.sqliteValue
            let convertedDate = Date(sqliteValue: sqliteValue)
            print("  After SQLite conversion: \(String(describing: convertedDate))")
            
            if let convertedDate = convertedDate {
                let difference = abs(date.timeIntervalSince1970 - convertedDate.timeIntervalSince1970)
                print("  Difference: \(difference) seconds")
                #expect(difference < 0.001)
            }
        }
    }
}