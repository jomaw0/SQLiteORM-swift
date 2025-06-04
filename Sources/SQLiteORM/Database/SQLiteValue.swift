import Foundation
import SQLite3

/// Type-safe representation of SQLite values
/// Handles conversion between Swift types and SQLite storage types
public enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    
    /// Bind this value to a prepared statement
    /// - Parameters:
    ///   - statement: The prepared statement
    ///   - index: The parameter index (1-based)
    /// - Returns: SQLite result code
    func bind(to statement: OpaquePointer?, at index: Int32) -> Int32 {
        switch self {
        case .null:
            return sqlite3_bind_null(statement, index)
        case .integer(let value):
            return sqlite3_bind_int64(statement, index, value)
        case .real(let value):
            return sqlite3_bind_double(statement, index, value)
        case .text(let value):
            return sqlite3_bind_text(statement, index, value, -1, nil)
        case .blob(let data):
            return data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), nil)
            }
        }
    }
    
    /// Create a SQLiteValue from a column in a result set
    /// - Parameters:
    ///   - statement: The prepared statement
    ///   - index: The column index (0-based)
    /// - Returns: The SQLite value
    static func fromColumn(statement: OpaquePointer?, index: Int32) -> SQLiteValue {
        let type = sqlite3_column_type(statement, index)
        
        switch type {
        case SQLITE_NULL:
            return .null
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            if let cString = sqlite3_column_text(statement, index) {
                return .text(String(cString: cString))
            } else {
                return .null
            }
        case SQLITE_BLOB:
            if let bytes = sqlite3_column_blob(statement, index) {
                let count = Int(sqlite3_column_bytes(statement, index))
                return .blob(Data(bytes: bytes, count: count))
            } else {
                return .null
            }
        default:
            return .null
        }
    }
}

/// Protocol for types that can be converted to/from SQLiteValue
public protocol SQLiteConvertible {
    init?(sqliteValue: SQLiteValue)
    var sqliteValue: SQLiteValue { get }
}

// MARK: - SQLiteConvertible Implementations

extension Int: SQLiteConvertible {
    public init?(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .integer(let value):
            self = Int(value)
        case .real(let value):
            self = Int(value)
        default:
            return nil
        }
    }
    
    public var sqliteValue: SQLiteValue {
        .integer(Int64(self))
    }
}

extension Int32: SQLiteConvertible {
    public init?(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .integer(let value):
            self = Int32(value)
        default:
            return nil
        }
    }
    
    public var sqliteValue: SQLiteValue {
        .integer(Int64(self))
    }
}

extension Int64: SQLiteConvertible {
    public init?(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .integer(let value):
            self = value
        default:
            return nil
        }
    }
    
    public var sqliteValue: SQLiteValue {
        .integer(self)
    }
}

extension Double: SQLiteConvertible {
    public init?(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .real(let value):
            self = value
        case .integer(let value):
            self = Double(value)
        default:
            return nil
        }
    }
    
    public var sqliteValue: SQLiteValue {
        .real(self)
    }
}

extension Float: SQLiteConvertible {
    public init?(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .real(let value):
            self = Float(value)
        case .integer(let value):
            self = Float(value)
        default:
            return nil
        }
    }
    
    public var sqliteValue: SQLiteValue {
        .real(Double(self))
    }
}

extension String: SQLiteConvertible {
    public init?(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .text(let value):
            self = value
        default:
            return nil
        }
    }
    
    public var sqliteValue: SQLiteValue {
        .text(self)
    }
}

extension Bool: SQLiteConvertible {
    public init?(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .integer(let value):
            self = value != 0
        default:
            return nil
        }
    }
    
    public var sqliteValue: SQLiteValue {
        .integer(self ? 1 : 0)
    }
}

extension Data: SQLiteConvertible {
    public init?(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .blob(let value):
            self = value
        default:
            return nil
        }
    }
    
    public var sqliteValue: SQLiteValue {
        .blob(self)
    }
}

extension Date: SQLiteConvertible {
    public init?(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .real(let value):
            self = Date(timeIntervalSince1970: value)
        case .integer(let value):
            self = Date(timeIntervalSince1970: Double(value))
        case .text(let value):
            // Try to parse ISO8601 date string
            if let date = DateFormatter.iso8601Full.date(from: value) {
                self = date
            } else if let date = DateFormatter.iso8601.date(from: value) {
                self = date
            } else {
                return nil
            }
        default:
            return nil
        }
    }
    
    public var sqliteValue: SQLiteValue {
        .real(self.timeIntervalSince1970)
    }
}

extension Optional: SQLiteConvertible where Wrapped: SQLiteConvertible {
    public init?(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .null:
            self = nil
        default:
            if let value = Wrapped(sqliteValue: sqliteValue) {
                self = value
            } else {
                return nil
            }
        }
    }
    
    public var sqliteValue: SQLiteValue {
        switch self {
        case .none:
            return .null
        case .some(let value):
            return value.sqliteValue
        }
    }
}

extension UUID: SQLiteConvertible {
    public init?(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .text(let value):
            self.init(uuidString: value)
        default:
            return nil
        }
    }
    
    public var sqliteValue: SQLiteValue {
        .text(self.uuidString)
    }
}

/// Date formatter extensions for SQLite date handling
extension DateFormatter {
    static let iso8601Full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}