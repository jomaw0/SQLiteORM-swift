/// SQLiteORM - A type-safe, easy-to-use SQLite ORM for Swift
/// 
/// Features:
/// - Type-safe SQL queries with compile-time validation
/// - Swift actor pattern for thread-safe concurrent access
/// - Automatic model mapping with Swift macros
/// - Comprehensive error handling with Result types
/// - Built-in migration system
/// - Support for various data types including custom date formats
/// - Zero external dependencies (uses built-in SQLite3)

// Re-export all public APIs
@_exported import Foundation

// Core types are already defined in Result.swift

// Re-export from submodules
// Note: Since we're using submodules, these are already available
// This file serves as the main entry point and documentation