import Foundation

/// Apply to a struct to generate ORMTable conformance boilerplate
/// Automatically generates id property, column mappings, indexes, and constraints
@attached(member, names: named(id), named(columnMappings), named(indexes), named(uniqueConstraints))
public macro ORMTable() = #externalMacro(module: "SQLiteORMMacros", type: "ORMTableMacro")

/// Specify a custom table name for the ORMTable
/// - Parameter name: The table name to use in the database
@attached(member, names: named(tableName))
public macro ORMTableName(_ name: String) = #externalMacro(module: "SQLiteORMMacros", type: "ORMTableNameMacro")

/// Map a property to a different column name in the database
/// - Parameter name: The column name in the database
@attached(peer)
public macro ORMColumn(_ name: String) = #externalMacro(module: "SQLiteORMMacros", type: "ORMColumnMacro")

/// Mark a property as the primary key with custom type
/// - Parameter type: The type of the primary key (defaults to Int)
@attached(peer)
public macro ORMPrimaryKey() = #externalMacro(module: "SQLiteORMMacros", type: "ORMPrimaryKeyMacro")

/// Create a database index on this property
@attached(peer)
public macro ORMIndexed() = #externalMacro(module: "SQLiteORMMacros", type: "ORMIndexedMacro")

/// Add a unique constraint to this property
@attached(peer)
public macro ORMUnique() = #externalMacro(module: "SQLiteORMMacros", type: "ORMUniqueMacro")

// MARK: - Relationship Macros

/// Define a belongs-to relationship (foreign key reference)
/// Automatically generates the foreign key property and relationship accessors
/// - Parameter relatedType: The type this table belongs to
/// - Parameter foreignKey: Custom foreign key column name (optional)
@attached(accessor)
public macro ORMBelongsTo<T: ORMTable>(_ relatedType: T.Type, foreignKey: String? = nil) = #externalMacro(module: "SQLiteORMMacros", type: "ORMBelongsToMacro")

/// Define a has-many relationship (one-to-many)
/// Provides lazy loading of related tables
/// - Parameter relatedType: The type of related tables
/// - Parameter foreignKey: The foreign key on the related table pointing to this table
@attached(accessor)
public macro ORMHasMany<T: ORMTable>(_ relatedType: T.Type, foreignKey: String) = #externalMacro(module: "SQLiteORMMacros", type: "ORMHasManyMacro")

/// Define a has-one relationship (one-to-one)
/// Provides lazy loading of a single related table
/// - Parameter relatedType: The type of the related table
/// - Parameter foreignKey: The foreign key on the related table pointing to this table
@attached(accessor)
public macro ORMHasOne<T: ORMTable>(_ relatedType: T.Type, foreignKey: String) = #externalMacro(module: "SQLiteORMMacros", type: "ORMHasOneMacro")

/// Define a many-to-many relationship through a junction table
/// Provides lazy loading of related tables through an intermediate table
/// - Parameter relatedType: The type of related tables
/// - Parameter through: The name of the junction table
@attached(accessor)
public macro ORMManyToMany<T: ORMTable>(_ relatedType: T.Type, through: String) = #externalMacro(module: "SQLiteORMMacros", type: "ORMManyToManyMacro")

// MARK: - Backward Compatibility

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMTable")
public macro Model() = #externalMacro(module: "SQLiteORMMacros", type: "ORMTableMacro")

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMTableName")
public macro Table(_ name: String) = #externalMacro(module: "SQLiteORMMacros", type: "ORMTableNameMacro")

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMColumn")
public macro Column(_ name: String) = #externalMacro(module: "SQLiteORMMacros", type: "ORMColumnMacro")

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMPrimaryKey")
public macro PrimaryKey() = #externalMacro(module: "SQLiteORMMacros", type: "ORMPrimaryKeyMacro")

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMIndexed")
public macro Indexed() = #externalMacro(module: "SQLiteORMMacros", type: "ORMIndexedMacro")

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMUnique")
public macro Unique() = #externalMacro(module: "SQLiteORMMacros", type: "ORMUniqueMacro")

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMBelongsTo")
@attached(accessor)
public macro BelongsTo<T: ORMTable>(_ relatedType: T.Type, foreignKey: String? = nil) = #externalMacro(module: "SQLiteORMMacros", type: "ORMBelongsToMacro")

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMHasMany")
@attached(accessor)
public macro HasMany<T: ORMTable>(_ relatedType: T.Type, foreignKey: String) = #externalMacro(module: "SQLiteORMMacros", type: "ORMHasManyMacro")

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMHasOne")
@attached(accessor)
public macro HasOne<T: ORMTable>(_ relatedType: T.Type, foreignKey: String) = #externalMacro(module: "SQLiteORMMacros", type: "ORMHasOneMacro")

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMManyToMany")
@attached(accessor)
public macro ManyToMany<T: ORMTable>(_ relatedType: T.Type, through: String) = #externalMacro(module: "SQLiteORMMacros", type: "ORMManyToManyMacro")