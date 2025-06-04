import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Main compiler plugin that provides SQLiteORM macros
@main
struct SQLiteORMPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ModelMacro.self,
        TableMacro.self,
        ColumnMacro.self,
        PrimaryKeyMacro.self,
        IndexedMacro.self,
        UniqueMacro.self
    ]
}

/// @Model macro that generates boilerplate code for ORM models
public struct ModelMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.onlyApplicableToStruct
        }
        
        var members: [DeclSyntax] = []
        
        // Check if id property exists
        let hasIdProperty = structDecl.memberBlock.members.contains { member in
            if let variable = member.decl.as(VariableDeclSyntax.self),
               let binding = variable.bindings.first,
               let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                return pattern.identifier.text == "id"
            }
            return false
        }
        
        // Add id property if it doesn't exist
        if !hasIdProperty {
            let idProperty = DeclSyntax("""
                /// The primary key for this model
                public var id: Int = 0
                """)
            members.append(idProperty)
        }
        
        // Generate column mappings based on @Column attributes
        let columnMappings = generateColumnMappings(from: structDecl)
        if !columnMappings.isEmpty {
            let mappingsProperty = DeclSyntax("""
                /// Custom column mappings
                public static var columnMappings: [String: String]? {
                    [
                        \(raw: columnMappings.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ",\n        "))
                    ]
                }
                """)
            members.append(mappingsProperty)
        }
        
        // Generate indexes based on @Indexed attributes
        let indexes = generateIndexes(from: structDecl)
        if !indexes.isEmpty {
            let indexesProperty = DeclSyntax("""
                /// Database indexes
                public static var indexes: [Index] {
                    [
                        \(raw: indexes.joined(separator: ",\n        "))
                    ]
                }
                """)
            members.append(indexesProperty)
        }
        
        // Generate unique constraints based on @Unique attributes
        let uniqueConstraints = generateUniqueConstraints(from: structDecl)
        if !uniqueConstraints.isEmpty {
            let constraintsProperty = DeclSyntax("""
                /// Unique constraints
                public static var uniqueConstraints: [UniqueConstraint] {
                    [
                        \(raw: uniqueConstraints.joined(separator: ",\n        "))
                    ]
                }
                """)
            members.append(constraintsProperty)
        }
        
        return members
    }
    
    private static func generateColumnMappings(from structDecl: StructDeclSyntax) -> [String: String] {
        var mappings: [String: String] = [:]
        
        for member in structDecl.memberBlock.members {
            if let variable = member.decl.as(VariableDeclSyntax.self),
               let binding = variable.bindings.first,
               let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                
                let propertyName = pattern.identifier.text
                
                // Look for @Column attribute
                for attribute in variable.attributes {
                    if let attributeSyntax = attribute.as(AttributeSyntax.self),
                       attributeSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Column",
                       let arguments = attributeSyntax.arguments?.as(LabeledExprListSyntax.self),
                       let firstArg = arguments.first,
                       let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
                       let value = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text {
                        mappings[propertyName] = value
                    }
                }
            }
        }
        
        return mappings
    }
    
    private static func generateIndexes(from structDecl: StructDeclSyntax) -> [String] {
        var indexes: [String] = []
        let structName = structDecl.name.text
        
        for member in structDecl.memberBlock.members {
            if let variable = member.decl.as(VariableDeclSyntax.self),
               let binding = variable.bindings.first,
               let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                
                let propertyName = pattern.identifier.text
                
                // Look for @Indexed attribute
                for attribute in variable.attributes {
                    if let attributeSyntax = attribute.as(AttributeSyntax.self),
                       attributeSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Indexed" {
                        let indexName = "idx_\(structName.lowercased())_\(propertyName.lowercased())"
                        indexes.append("Index(name: \"\(indexName)\", columns: [\"\(propertyName)\"])")
                    }
                }
            }
        }
        
        return indexes
    }
    
    private static func generateUniqueConstraints(from structDecl: StructDeclSyntax) -> [String] {
        var constraints: [String] = []
        let structName = structDecl.name.text
        
        for member in structDecl.memberBlock.members {
            if let variable = member.decl.as(VariableDeclSyntax.self),
               let binding = variable.bindings.first,
               let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                
                let propertyName = pattern.identifier.text
                
                // Look for @Unique attribute
                for attribute in variable.attributes {
                    if let attributeSyntax = attribute.as(AttributeSyntax.self),
                       attributeSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Unique" {
                        let constraintName = "uniq_\(structName.lowercased())_\(propertyName.lowercased())"
                        constraints.append("UniqueConstraint(name: \"\(constraintName)\", columns: [\"\(propertyName)\"])")
                    }
                }
            }
        }
        
        return constraints
    }
}

/// @Table macro to specify custom table name
public struct TableMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let firstArg = arguments.first,
              let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
              let tableName = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text else {
            throw MacroError.invalidArguments
        }
        
        return [
            DeclSyntax("""
                /// The database table name
                public static var tableName: String { "\(raw: tableName)" }
                """)
        ]
    }
}

/// @Column macro to specify custom column name
public struct ColumnMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This is a marker macro, actual work is done in ModelMacro
        return []
    }
}

/// @PrimaryKey macro to mark primary key with custom type
public struct PrimaryKeyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This is a marker macro, actual work is done in ModelMacro
        return []
    }
}

/// @Indexed macro to create database index
public struct IndexedMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This is a marker macro, actual work is done in ModelMacro
        return []
    }
}

/// @Unique macro to create unique constraint
public struct UniqueMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This is a marker macro, actual work is done in ModelMacro
        return []
    }
}

/// Macro errors
enum MacroError: Error, CustomStringConvertible {
    case onlyApplicableToStruct
    case invalidArguments
    
    var description: String {
        switch self {
        case .onlyApplicableToStruct:
            return "@Model can only be applied to structs"
        case .invalidArguments:
            return "Invalid macro arguments"
        }
    }
}