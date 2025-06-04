import Foundation

/// Encoder for converting Model instances to database values
public struct ModelEncoder {
    /// Encode a model to a dictionary of column names to SQLite values
    /// - Parameter model: The model to encode
    /// - Returns: Dictionary of column names to values
    /// - Throws: EncodingError if encoding fails
    public func encode<T: Model>(_ model: T) throws -> [String: SQLiteValue] {
        let data = try JSONEncoder().encode(model)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        var result: [String: SQLiteValue] = [:]
        let columnMappings = T.columnMappings ?? [:]
        
        for (key, value) in json {
            let columnName = columnMappings[key] ?? key
            result[columnName] = convertToSQLiteValue(value)
        }
        
        return result
    }
    
    /// Convert a Swift value to SQLiteValue
    private func convertToSQLiteValue(_ value: Any) -> SQLiteValue {
        switch value {
        case let int as Int:
            return .integer(Int64(int))
        case let int32 as Int32:
            return .integer(Int64(int32))
        case let int64 as Int64:
            return .integer(int64)
        case let double as Double:
            return .real(double)
        case let float as Float:
            return .real(Double(float))
        case let string as String:
            return .text(string)
        case let bool as Bool:
            return .integer(bool ? 1 : 0)
        case let data as Data:
            return .blob(data)
        case let date as Date:
            return .real(date.timeIntervalSince1970)
        case is NSNull:
            return .null
        default:
            // Try to convert to string as fallback
            return .text(String(describing: value))
        }
    }
}

/// Decoder for converting database values to Model instances
public struct ModelDecoder {
    /// Decode a model from a row dictionary
    /// - Parameters:
    ///   - type: The model type to decode
    ///   - row: Dictionary of column names to SQLite values
    /// - Returns: The decoded model
    /// - Throws: DecodingError if decoding fails
    public func decode<T: Model>(_ type: T.Type, from row: [String: SQLiteValue]) throws -> T {
        // Reverse column mappings
        let columnMappings = T.columnMappings ?? [:]
        let reverseMappings = Dictionary(uniqueKeysWithValues: columnMappings.map { ($1, $0) })
        
        var jsonDict: [String: Any] = [:]
        
        for (columnName, value) in row {
            let propertyName = reverseMappings[columnName] ?? columnName
            jsonDict[propertyName] = convertFromSQLiteValue(value)
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
        
        // Configure decoder for dates
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            
            // Try to decode as TimeInterval (Unix timestamp)
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            
            // Try to decode as ISO8601 string
            if let dateString = try? container.decode(String.self) {
                if let date = DateFormatter.iso8601Full.date(from: dateString) {
                    return date
                }
                if let date = DateFormatter.iso8601.date(from: dateString) {
                    return date
                }
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode Date")
        }
        
        return try decoder.decode(T.self, from: jsonData)
    }
    
    /// Convert SQLiteValue to appropriate Swift type for JSON serialization
    private func convertFromSQLiteValue(_ value: SQLiteValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .integer(let int):
            return int
        case .real(let double):
            return double
        case .text(let string):
            return string
        case .blob(let data):
            return data
        }
    }
}