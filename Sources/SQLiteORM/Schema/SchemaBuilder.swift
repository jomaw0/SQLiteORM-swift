import Foundation

/// Schema builder for generating SQL DDL statements
public struct SchemaBuilder {
    /// Generate CREATE TABLE statement for a model
    /// - Parameter type: The model type
    /// - Returns: SQL CREATE TABLE statement
    public static func createTable<T: ORMTable>(for type: T.Type) -> String {
        var sql = "CREATE TABLE IF NOT EXISTS \(T.tableName) ("
        var columns: [String] = []
        
        // Get property info using Mirror
        let dummyInstance: T
        do {
            dummyInstance = try T.init(from: DummyDecoder())
        } catch {
            // Fallback to basic id field
            return "CREATE TABLE IF NOT EXISTS \(T.tableName) (id INTEGER PRIMARY KEY AUTOINCREMENT)"
        }
        
        let mirror = Mirror(reflecting: dummyInstance)
        let columnMappings = T.columnMappings ?? [:]
        
        for child in mirror.children {
            guard let propertyName = child.label else { continue }
            
            let columnName = columnMappings[propertyName] ?? propertyName
            let columnType = sqlType(for: child.value)
            
            if propertyName == "id" {
                columns.append("\(columnName) \(columnType) PRIMARY KEY")
                
                // Add AUTOINCREMENT for integer primary keys
                if columnType == "INTEGER" {
                    columns[columns.count - 1] += " AUTOINCREMENT"
                }
            } else {
                var columnDef = "\(columnName) \(columnType)"
                
                // Check if property is optional
                if isOptional(child.value) {
                    columnDef += " NULL"
                } else {
                    columnDef += " NOT NULL"
                }
                
                columns.append(columnDef)
            }
        }
        
        sql += columns.joined(separator: ", ")
        
        // Add unique constraints
        for constraint in T.uniqueConstraints {
            sql += ", CONSTRAINT \(constraint.name) UNIQUE (\(constraint.columns.joined(separator: ", ")))"
        }
        
        sql += ")"
        
        return sql
    }
    
    /// Generate CREATE INDEX statements for a model
    /// - Parameter type: The model type
    /// - Returns: Array of SQL CREATE INDEX statements
    public static func createIndexes<T: ORMTable>(for type: T.Type) -> [String] {
        T.indexes.map { index in
            let unique = index.unique ? "UNIQUE " : ""
            return "CREATE \(unique)INDEX IF NOT EXISTS \(index.name) ON \(T.tableName) (\(index.columns.joined(separator: ", ")))"
        }
    }
    
    /// Determine SQL type for a Swift value
    private static func sqlType(for value: Any) -> String {
        switch value {
        case is Int, is Int32, is Int64, is Bool:
            return "INTEGER"
        case is Double, is Float:
            return "REAL"
        case is String, is UUID:
            return "TEXT"
        case is Data:
            return "BLOB"
        case is Date:
            return "REAL"  // Store as Unix timestamp
        default:
            // Check if it's an optional type
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional {
                // For optional types, we need to determine the wrapped type
                // based on the Swift type name, not the runtime value
                let typeName = String(describing: type(of: value))
                if typeName.contains("Date") {
                    return "REAL"
                } else if typeName.contains("Data") {
                    return "BLOB"
                } else if typeName.contains("Int") || typeName.contains("Bool") {
                    return "INTEGER"
                } else if typeName.contains("Double") || typeName.contains("Float") {
                    return "REAL"
                } else {
                    return "TEXT"
                }
            }
            return "TEXT"  // Default to TEXT
        }
    }
    
    /// Check if a value is optional
    private static func isOptional(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional
    }
}

/// Dummy decoder for creating model instances to inspect properties
private struct DummyDecoder: Decoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    
    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(DummyKeyedContainer<Key>())
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        DummyUnkeyedContainer()
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        DummySingleValueContainer()
    }
}

private struct DummyKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    var codingPath: [CodingKey] = []
    var allKeys: [Key] = []
    
    func contains(_ key: Key) -> Bool { true }
    func decodeNil(forKey key: Key) throws -> Bool { true }
    
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        if type == Int.self {
            return 0 as! T
        } else if type == Int32.self {
            return Int32(0) as! T
        } else if type == Int64.self {
            return Int64(0) as! T
        } else if type == Double.self {
            return 0.0 as! T
        } else if type == Float.self {
            return Float(0.0) as! T
        } else if type == String.self {
            return "" as! T
        } else if type == Bool.self {
            return false as! T
        } else if type == Date.self {
            return Date() as! T
        } else if type == Data.self {
            return Data() as! T
        } else if type == UUID.self {
            return UUID() as! T
        } else {
            return try T(from: DummyDecoder())
        }
    }
    
    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        KeyedDecodingContainer(DummyKeyedContainer<NestedKey>())
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        DummyUnkeyedContainer()
    }
    
    func superDecoder() throws -> Decoder { DummyDecoder() }
    func superDecoder(forKey key: Key) throws -> Decoder { DummyDecoder() }
}

private struct DummyUnkeyedContainer: UnkeyedDecodingContainer {
    var codingPath: [CodingKey] = []
    var count: Int? = 0
    var currentIndex: Int = 0
    var isAtEnd: Bool { true }
    
    mutating func decodeNil() throws -> Bool { true }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try T(from: DummyDecoder())
    }
    
    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        KeyedDecodingContainer(DummyKeyedContainer<NestedKey>())
    }
    
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        DummyUnkeyedContainer()
    }
    
    mutating func superDecoder() throws -> Decoder { DummyDecoder() }
}

private struct DummySingleValueContainer: SingleValueDecodingContainer {
    var codingPath: [CodingKey] = []
    
    func decodeNil() -> Bool { true }
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try T(from: DummyDecoder())
    }
}