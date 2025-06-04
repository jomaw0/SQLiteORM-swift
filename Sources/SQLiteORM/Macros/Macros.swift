import Foundation

/// Apply to a struct to generate Model conformance boilerplate
/// Automatically generates id property, column mappings, indexes, and constraints
@attached(member, names: named(id), named(columnMappings), named(indexes), named(uniqueConstraints))
public macro Model() = #externalMacro(module: "SQLiteORMMacros", type: "ModelMacro")

/// Specify a custom table name for the model
/// - Parameter name: The table name to use in the database
@attached(member, names: named(tableName))
public macro Table(_ name: String) = #externalMacro(module: "SQLiteORMMacros", type: "TableMacro")

/// Map a property to a different column name in the database
/// - Parameter name: The column name in the database
@attached(peer)
public macro Column(_ name: String) = #externalMacro(module: "SQLiteORMMacros", type: "ColumnMacro")

/// Mark a property as the primary key with custom type
/// - Parameter type: The type of the primary key (defaults to Int)
@attached(peer)
public macro PrimaryKey() = #externalMacro(module: "SQLiteORMMacros", type: "PrimaryKeyMacro")

/// Create a database index on this property
@attached(peer)
public macro Indexed() = #externalMacro(module: "SQLiteORMMacros", type: "IndexedMacro")

/// Add a unique constraint to this property
@attached(peer)
public macro Unique() = #externalMacro(module: "SQLiteORMMacros", type: "UniqueMacro")