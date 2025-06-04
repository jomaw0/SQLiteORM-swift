import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Main compiler plugin that provides SQLiteORM macros
@main
struct SQLiteORMPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ORMTableMacro.self,
        ORMTableNameMacro.self,
        ORMColumnMacro.self,
        ORMPrimaryKeyMacro.self,
        ORMIndexedMacro.self,
        ORMUniqueMacro.self,
        ORMBelongsToMacro.self,
        ORMHasManyMacro.self,
        ORMHasOneMacro.self,
        ORMManyToManyMacro.self
    ]
}

/// @ORMTable macro that generates boilerplate code for ORM models
public struct ORMTableMacro: MemberMacro {
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
        
        // Generate foreign keys and relationship properties
        let relationshipCode = generateRelationships(from: structDecl)
        members.append(contentsOf: relationshipCode)
        
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
    
    private static func generateRelationships(from structDecl: StructDeclSyntax) -> [DeclSyntax] {
        var members: [DeclSyntax] = []
        
        for member in structDecl.memberBlock.members {
            if let variable = member.decl.as(VariableDeclSyntax.self),
               let binding = variable.bindings.first,
               let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                
                let propertyName = pattern.identifier.text
                
                // Check for relationship attributes
                for attribute in variable.attributes {
                    if let attributeSyntax = attribute.as(AttributeSyntax.self),
                       let attributeTypeName = attributeSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text {
                        
                        switch attributeTypeName {
                        case "BelongsTo":
                            if let foreignKeyProperty = generateBelongsToForeignKey(
                                from: attributeSyntax,
                                propertyName: propertyName
                            ) {
                                members.append(foreignKeyProperty)
                            }
                            
                        case "HasMany":
                            // HasMany doesn't need foreign key on this model
                            break
                            
                        case "HasOne":
                            // HasOne doesn't need foreign key on this model
                            break
                            
                        case "ManyToMany":
                            // ManyToMany relationships use junction tables
                            break
                            
                        default:
                            break
                        }
                    }
                }
            }
        }
        
        return members
    }
    
    private static func generateBelongsToForeignKey(
        from attribute: AttributeSyntax,
        propertyName: String
    ) -> DeclSyntax? {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }
        
        var foreignKeyName: String?
        
        // Look for foreignKey parameter
        for argument in arguments {
            if argument.label?.text == "foreignKey",
               let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
               let value = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text {
                foreignKeyName = value
                break
            }
        }
        
        // Default foreign key name if not specified
        let finalForeignKeyName = foreignKeyName ?? "\(propertyName)Id"
        
        return DeclSyntax("""
            /// Foreign key for \(raw: propertyName) relationship
            public var \(raw: finalForeignKeyName): Int = 0
            """)
    }
}

/// @Table macro to specify custom table name
public struct ORMTableNameMacro: MemberMacro {
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
public struct ORMColumnMacro: PeerMacro {
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
public struct ORMPrimaryKeyMacro: PeerMacro {
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
public struct ORMIndexedMacro: PeerMacro {
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
public struct ORMUniqueMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This is a marker macro, actual work is done in ModelMacro
        return []
    }
}

// MARK: - Relationship Macros

/// @BelongsTo macro for defining belongs-to relationships
public struct ORMBelongsToMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            throw MacroError.invalidProperty
        }
        
        let propertyName = pattern.identifier.text
        var foreignKeyName = "\(propertyName)Id"
        
        // Parse arguments to get foreign key name
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                if argument.label?.text == "foreignKey",
                   let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                   let value = stringLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text {
                    foreignKeyName = value
                    break
                }
            }
        }
        
        return [
            AccessorDeclSyntax(accessorSpecifier: .keyword(.get)) {
                """
                return _\(raw: propertyName)
                """
            },
            AccessorDeclSyntax(accessorSpecifier: .keyword(.set)) {
                """
                _\(raw: propertyName) = newValue
                if let newValue = newValue {
                    \(raw: foreignKeyName) = newValue.id as! Int
                } else {
                    \(raw: foreignKeyName) = 0
                }
                """
            }
        ]
    }
}

/// @HasMany macro for defining has-many relationships
public struct ORMHasManyMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        return [
            AccessorDeclSyntax(accessorSpecifier: .keyword(.get)) {
                """
                return _\(raw: getPropertyName(from: declaration))
                """
            },
            AccessorDeclSyntax(accessorSpecifier: .keyword(.set)) {
                """
                _\(raw: getPropertyName(from: declaration)) = newValue
                """
            }
        ]
    }
    
    private static func getPropertyName(from declaration: some DeclSyntaxProtocol) -> String {
        if let varDecl = declaration.as(VariableDeclSyntax.self),
           let binding = varDecl.bindings.first,
           let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
            return pattern.identifier.text
        }
        return "unknown"
    }
}

/// @HasOne macro for defining has-one relationships
public struct ORMHasOneMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        return [
            AccessorDeclSyntax(accessorSpecifier: .keyword(.get)) {
                """
                return _\(raw: getPropertyName(from: declaration))
                """
            },
            AccessorDeclSyntax(accessorSpecifier: .keyword(.set)) {
                """
                _\(raw: getPropertyName(from: declaration)) = newValue
                """
            }
        ]
    }
    
    private static func getPropertyName(from declaration: some DeclSyntaxProtocol) -> String {
        if let varDecl = declaration.as(VariableDeclSyntax.self),
           let binding = varDecl.bindings.first,
           let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
            return pattern.identifier.text
        }
        return "unknown"
    }
}

/// @ManyToMany macro for defining many-to-many relationships
public struct ORMManyToManyMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        return [
            AccessorDeclSyntax(accessorSpecifier: .keyword(.get)) {
                """
                return _\(raw: getPropertyName(from: declaration))
                """
            },
            AccessorDeclSyntax(accessorSpecifier: .keyword(.set)) {
                """
                _\(raw: getPropertyName(from: declaration)) = newValue
                """
            }
        ]
    }
    
    private static func getPropertyName(from declaration: some DeclSyntaxProtocol) -> String {
        if let varDecl = declaration.as(VariableDeclSyntax.self),
           let binding = varDecl.bindings.first,
           let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
            return pattern.identifier.text
        }
        return "unknown"
    }
}

/// Macro errors
enum MacroError: Error, CustomStringConvertible {
    case onlyApplicableToStruct
    case invalidArguments
    case invalidProperty
    
    var description: String {
        switch self {
        case .onlyApplicableToStruct:
            return "@Model can only be applied to structs"
        case .invalidArguments:
            return "Invalid macro arguments"
        case .invalidProperty:
            return "Macro can only be applied to variable properties"
        }
    }
}

