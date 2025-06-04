import Testing
@testable import SQLiteORM
import Foundation

// MARK: - Test Models with Relationships

@Model
struct Author: Model {
    typealias IDType = Int
    var id: Int = 0
    var name: String
    var email: String
    
    init(name: String, email: String) {
        self.name = name
        self.email = email
    }
}

@Model
struct Book: Model {
    typealias IDType = Int
    var id: Int = 0
    var title: String
    var isbn: String
    var authorId: Int = 0  // Foreign key
    
    init(title: String, isbn: String) {
        self.title = title
        self.isbn = isbn
    }
}

@Model
struct AuthorProfile: Model {
    typealias IDType = Int
    var id: Int = 0
    var bio: String
    var website: String?
    var authorId: Int = 0  // Foreign key
    
    init(bio: String, website: String? = nil) {
        self.bio = bio
        self.website = website
    }
}

@Model
struct Tag: Model {
    typealias IDType = Int
    var id: Int = 0
    var name: String
    var color: String
    
    init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}

// Junction table for many-to-many relationship
@Model
struct BookTag: Model {
    typealias IDType = Int
    var id: Int = 0
    var bookId: Int
    var tagId: Int
    var assignedAt: Date
    
    static var tableName: String { "book_tags" }
    static var uniqueConstraints: [UniqueConstraint] {
        [UniqueConstraint(name: "uniq_book_tag", columns: ["bookId", "tagId"])]
    }
    
    init(bookId: Int, tagId: Int, assignedAt: Date = Date()) {
        self.bookId = bookId
        self.tagId = tagId
        self.assignedAt = assignedAt
    }
}

// MARK: - Helper Functions

func setupRelationshipTestEnvironment() async throws -> (URL, ORM) {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SQLiteORM_Relationship_Tests_\(UUID().uuidString)")
    
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    
    let dbPath = tempDirectory.appendingPathComponent("test.sqlite").path
    let orm = ORM(path: dbPath, enableDiskStorage: false) // Disable disk storage for simpler tests
    
    let openResult = await orm.open()
    switch openResult {
    case .success:
        break
    case .failure(let error):
        throw error
    }
    
    // Create all tables
    let createResult = await orm.createTables(for: [Author.self, Book.self, AuthorProfile.self, Tag.self, BookTag.self])
    switch createResult {
    case .success:
        break
    case .failure(let error):
        throw error
    }
    
    return (tempDirectory, orm)
}

func cleanupRelationshipTestEnvironment(tempDirectory: URL, orm: ORM) async {
    let _ = await orm.close()
    try? FileManager.default.removeItem(at: tempDirectory)
}

// MARK: - Tests

@Test("Foreign key properties work correctly")
func foreignKeyProperties() async throws {
    let (tempDirectory, orm) = try await setupRelationshipTestEnvironment()
    defer { Task { await cleanupRelationshipTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    // Test basic foreign key functionality
    var book = Book(title: "Test Book", isbn: "123456789")
    
    // Test that foreign key property exists and has default value
    #expect(book.authorId == 0) // Default value
    
    // Test that we can set the foreign key manually
    book.authorId = 42
    #expect(book.authorId == 42)
}

@Test("BelongsTo relationship basic functionality")
func belongsToRelationship() async throws {
    let (tempDirectory, orm) = try await setupRelationshipTestEnvironment()
    defer { Task { await cleanupRelationshipTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    let authorRepo = await orm.repository(for: Author.self)
    let bookRepo = await orm.repository(for: Book.self)
    
    // Create and insert an author
    var author = Author(name: "Jane Doe", email: "jane@example.com")
    let authorResult = await authorRepo.insert(&author)
    #expect(authorResult.isSuccess)
    #expect(author.id > 0)
    
    // Create and insert a book with the author
    var book = Book(title: "Swift Programming", isbn: "978-0134610993")
    book.authorId = author.id
    let bookResult = await bookRepo.insert(&book)
    #expect(bookResult.isSuccess)
    #expect(book.id > 0)
    
    // Test finding the related author using repository methods
    let relatedAuthorResult = await bookRepo.findRelatedSingle(Author.self, foreignKey: "authorId", value: book.id)
    switch relatedAuthorResult {
    case .success(let foundAuthor):
        #expect(foundAuthor?.name == "Jane Doe")
        #expect(foundAuthor?.email == "jane@example.com")
    case .failure(let error):
        Issue.record("Failed to find related author: \(error)")
    }
}

@Test("HasMany relationship basic functionality")
func hasManyRelationship() async throws {
    let (tempDirectory, orm) = try await setupRelationshipTestEnvironment()
    defer { Task { await cleanupRelationshipTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    let authorRepo = await orm.repository(for: Author.self)
    let bookRepo = await orm.repository(for: Book.self)
    
    // Create and insert an author
    var author = Author(name: "John Smith", email: "john@example.com")
    let authorResult = await authorRepo.insert(&author)
    #expect(authorResult.isSuccess)
    
    // Create and insert multiple books by this author
    var book1 = Book(title: "Book One", isbn: "111111111")
    book1.authorId = author.id
    let book1Result = await bookRepo.insert(&book1)
    #expect(book1Result.isSuccess)
    
    var book2 = Book(title: "Book Two", isbn: "222222222")
    book2.authorId = author.id
    let book2Result = await bookRepo.insert(&book2)
    #expect(book2Result.isSuccess)
    
    // Test finding related books using repository methods
    let relatedBooksResult = await authorRepo.findRelated(Book.self, foreignKey: "authorId", value: author.id)
    switch relatedBooksResult {
    case .success(let books):
        #expect(books.count == 2)
        let titles = Set(books.map(\.title))
        #expect(titles.contains("Book One"))
        #expect(titles.contains("Book Two"))
    case .failure(let error):
        Issue.record("Failed to find related books: \(error)")
    }
}

@Test("HasOne relationship basic functionality")
func hasOneRelationship() async throws {
    let (tempDirectory, orm) = try await setupRelationshipTestEnvironment()
    defer { Task { await cleanupRelationshipTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    let authorRepo = await orm.repository(for: Author.self)
    let profileRepo = await orm.repository(for: AuthorProfile.self)
    
    // Create and insert an author
    var author = Author(name: "Alice Cooper", email: "alice@example.com")
    let authorResult = await authorRepo.insert(&author)
    #expect(authorResult.isSuccess)
    
    // Create and insert a profile for this author
    var profile = AuthorProfile(bio: "Famous author", website: "https://alice.com")
    profile.authorId = author.id
    let profileResult = await profileRepo.insert(&profile)
    #expect(profileResult.isSuccess)
    
    // Test finding the related profile using repository methods
    let relatedProfileResult = await authorRepo.findRelatedSingle(AuthorProfile.self, foreignKey: "authorId", value: author.id)
    switch relatedProfileResult {
    case .success(let foundProfile):
        #expect(foundProfile?.bio == "Famous author")
        #expect(foundProfile?.website == "https://alice.com")
    case .failure(let error):
        Issue.record("Failed to find related profile: \(error)")
    }
}

@Test("Repository relationship methods work correctly")
func repositoryRelationshipMethods() async throws {
    let (tempDirectory, orm) = try await setupRelationshipTestEnvironment()
    defer { Task { await cleanupRelationshipTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    let authorRepo = await orm.repository(for: Author.self)
    let bookRepo = await orm.repository(for: Book.self)
    
    // Create test data
    var author = Author(name: "Test Author", email: "test@example.com")
    let _ = await authorRepo.insert(&author)
    
    var book1 = Book(title: "First Book", isbn: "111")
    book1.authorId = author.id
    let _ = await bookRepo.insert(&book1)
    
    var book2 = Book(title: "Second Book", isbn: "222")
    book2.authorId = author.id
    let _ = await bookRepo.insert(&book2)
    
    // Test findRelated method
    let booksResult = await authorRepo.findRelated(Book.self, foreignKey: "authorId", value: author.id)
    switch booksResult {
    case .success(let books):
        #expect(books.count == 2)
    case .failure(let error):
        Issue.record("Failed to find related books: \(error)")
    }
    
    // Test findRelatedSingle method
    let authorResult = await bookRepo.findRelatedSingle(Author.self, foreignKey: "authorId", value: book1.authorId)
    switch authorResult {
    case .success(let foundAuthor):
        #expect(foundAuthor?.name == "Test Author")
    case .failure(let error):
        Issue.record("Failed to find related author: \(error)")
    }
}

@Test("Foreign key constraint behavior")
func foreignKeyConstraints() async throws {
    let (tempDirectory, orm) = try await setupRelationshipTestEnvironment()
    defer { Task { await cleanupRelationshipTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    let bookRepo = await orm.repository(for: Book.self)
    
    // Test that we can insert a book with a foreign key that doesn't exist
    // (SQLite doesn't enforce foreign key constraints by default)
    var book = Book(title: "Orphaned Book", isbn: "999999999")
    book.authorId = 999 // Non-existent author ID
    let insertResult = await bookRepo.insert(&book)
    #expect(insertResult.isSuccess)
    
    // Test finding the non-existent author
    let authorResult = await bookRepo.findRelatedSingle(Author.self, foreignKey: "authorId", value: book.authorId)
    switch authorResult {
    case .success(let foundAuthor):
        #expect(foundAuthor == nil) // Should be nil for non-existent foreign key
    case .failure(let error):
        Issue.record("Failed to query for non-existent author: \(error)")
    }
}

@Test("Basic relationship foreign key functionality")
func relationshipForeignKeyFunctionality() async throws {
    // Test basic foreign key functionality
    var book = Book(title: "Test", isbn: "123")
    var author = Author(name: "Test Author", email: "test@test.com")
    author.id = 5
    
    // Test foreign key assignment
    book.authorId = author.id
    #expect(book.authorId == 5)
    
    // Test profile foreign key
    var profile = AuthorProfile(bio: "Test bio")
    profile.authorId = author.id
    #expect(profile.authorId == 5)
}