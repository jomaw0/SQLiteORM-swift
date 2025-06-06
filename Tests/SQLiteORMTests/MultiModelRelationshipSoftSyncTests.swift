import Foundation
import Testing
@testable import SQLiteORM

@Suite("Multi-Model Relationship Soft Sync Tests")
struct MultiModelRelationshipSoftSyncTests {
    
    // MARK: - Test Models with Relationships
    
    @ORMTable
    struct Author: ORMTable {
        typealias IDType = Int
        
        var id: Int = 0
        var name: String = ""
        var email: String = ""
        var bio: String = ""
        
        // Sync properties
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, name: String = "", email: String = "", bio: String = "") {
            self.id = id
            self.name = name
            self.email = email
            self.bio = bio
            self.lastSyncTimestamp = nil
            self.isDirty = false
            self.syncStatus = .synced
            self.serverID = nil
        }
    }
    
    @ORMTable
    struct Category: ORMTable {
        typealias IDType = Int
        
        var id: Int = 0
        var name: String = ""
        var description: String = ""
        var color: String = ""
        
        // Sync properties
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, name: String = "", description: String = "", color: String = "") {
            self.id = id
            self.name = name
            self.description = description
            self.color = color
            self.lastSyncTimestamp = nil
            self.isDirty = false
            self.syncStatus = .synced
            self.serverID = nil
        }
    }
    
    @ORMTable
    struct Article: ORMTable {
        typealias IDType = Int
        
        var id: Int = 0
        var title: String = ""
        var content: String = ""
        var authorId: Int = 0  // Foreign key to Author
        var categoryId: Int = 0  // Foreign key to Category
        var publishedAt: Date? = nil
        var isPublished: Bool = false
        
        // Sync properties
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, title: String = "", content: String = "", authorId: Int = 0, categoryId: Int = 0, isPublished: Bool = false) {
            self.id = id
            self.title = title
            self.content = content
            self.authorId = authorId
            self.categoryId = categoryId
            self.isPublished = isPublished
            if isPublished {
                self.publishedAt = Date()
            }
            self.lastSyncTimestamp = nil
            self.isDirty = false
            self.syncStatus = .synced
            self.serverID = nil
        }
    }
    
    @ORMTable
    struct Comment: ORMTable {
        typealias IDType = Int
        
        var id: Int = 0
        var content: String = ""
        var authorId: Int = 0  // Foreign key to Author
        var articleId: Int = 0  // Foreign key to Article
        var createdAt: Date = Date()
        var isApproved: Bool = false
        
        // Sync properties
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, content: String = "", authorId: Int = 0, articleId: Int = 0, isApproved: Bool = false) {
            self.id = id
            self.content = content
            self.authorId = authorId
            self.articleId = articleId
            self.isApproved = isApproved
            self.lastSyncTimestamp = nil
            self.isDirty = false
            self.syncStatus = .synced
            self.serverID = nil
        }
    }
    
    @ORMTable
    struct Tag: ORMTable {
        typealias IDType = Int
        
        var id: Int = 0
        var name: String = ""
        var slug: String = ""
        
        // Sync properties
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, name: String = "", slug: String = "") {
            self.id = id
            self.name = name
            self.slug = slug
            self.lastSyncTimestamp = nil
            self.isDirty = false
            self.syncStatus = .synced
            self.serverID = nil
        }
    }
    
    @ORMTable
    struct ArticleTag: ORMTable {
        typealias IDType = Int
        
        var id: Int = 0
        var articleId: Int = 0  // Foreign key to Article
        var tagId: Int = 0      // Foreign key to Tag
        
        // Sync properties
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, articleId: Int = 0, tagId: Int = 0) {
            self.id = id
            self.articleId = articleId
            self.tagId = tagId
            self.lastSyncTimestamp = nil
            self.isDirty = false
            self.syncStatus = .synced
            self.serverID = nil
        }
    }
    
    // MARK: - Container Models for Complex API Responses
    
    struct BlogAPIResponse: Codable {
        let authors: [Author]
        let categories: [Category]
        let articles: [Article]
        let comments: [Comment]
        let tags: [Tag]
        let articleTags: [ArticleTag]
        let metadata: APIMetadata
        
        init(authors: [Author] = [], categories: [Category] = [], articles: [Article] = [], 
             comments: [Comment] = [], tags: [Tag] = [], articleTags: [ArticleTag] = [], 
             metadata: APIMetadata = APIMetadata()) {
            self.authors = authors
            self.categories = categories
            self.articles = articles
            self.comments = comments
            self.tags = tags
            self.articleTags = articleTags
            self.metadata = metadata
        }
    }
    
    struct PublishingWorkflowResponse: Codable {
        let workflowId: String
        let author: Author
        let category: Category
        let article: Article
        let initialComments: [Comment]
        let suggestedTags: [Tag]
        let success: Bool
        
        init(workflowId: String = "workflow-123", author: Author, category: Category, article: Article,
             initialComments: [Comment] = [], suggestedTags: [Tag] = [], success: Bool = true) {
            self.workflowId = workflowId
            self.author = author
            self.category = category
            self.article = article
            self.initialComments = initialComments
            self.suggestedTags = suggestedTags
            self.success = success
        }
    }
    
    struct APIMetadata: Codable {
        let timestamp: Date
        let version: String
        let totalRecords: Int
        
        init(timestamp: Date = Date(), version: String = "1.0", totalRecords: Int = 0) {
            self.timestamp = timestamp
            self.version = version
            self.totalRecords = totalRecords
        }
    }
    
    // MARK: - Setup Helper
    
    private func setupDatabase() async throws -> ORM {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        if case .failure(let error) = openResult {
            throw error
        }
        
        let createResult = await orm.createTables(
            Author.self, 
            Category.self, 
            Article.self, 
            Comment.self, 
            Tag.self, 
            ArticleTag.self
        )
        if case .failure(let error) = createResult {
            throw error
        }
        
        return orm
    }
    
    // MARK: - Relationship Validation Helpers
    
    private func verifyRelationshipIntegrity(orm: ORM, expectedAuthors: [Author], expectedCategories: [Category], expectedArticles: [Article]) async {
        let authorRepo = await orm.repository(for: Author.self)
        let categoryRepo = await orm.repository(for: Category.self)
        let articleRepo = await orm.repository(for: Article.self)
        
        // Verify all authors exist
        for expectedAuthor in expectedAuthors {
            let result = await authorRepo.find(id: expectedAuthor.id)
            if case .success(let author) = result {
                #expect(author?.name == expectedAuthor.name, "Author \(expectedAuthor.id) should have correct name")
            } else {
                Issue.record("Author \(expectedAuthor.id) should exist after sync")
            }
        }
        
        // Verify all categories exist
        for expectedCategory in expectedCategories {
            let result = await categoryRepo.find(id: expectedCategory.id)
            if case .success(let category) = result {
                #expect(category?.name == expectedCategory.name, "Category \(expectedCategory.id) should have correct name")
            } else {
                Issue.record("Category \(expectedCategory.id) should exist after sync")
            }
        }
        
        // Verify all articles exist with correct relationships
        for expectedArticle in expectedArticles {
            let result = await articleRepo.find(id: expectedArticle.id)
            if case .success(let article) = result {
                #expect(article?.title == expectedArticle.title, "Article \(expectedArticle.id) should have correct title")
                #expect(article?.authorId == expectedArticle.authorId, "Article \(expectedArticle.id) should reference correct author")
                #expect(article?.categoryId == expectedArticle.categoryId, "Article \(expectedArticle.id) should reference correct category")
                
                // Verify the referenced author exists
                let authorResult = await authorRepo.find(id: expectedArticle.authorId)
                #expect(authorResult.isSuccess, "Referenced author \(expectedArticle.authorId) should exist")
                
                // Verify the referenced category exists
                let categoryResult = await categoryRepo.find(id: expectedArticle.categoryId)
                #expect(categoryResult.isSuccess, "Referenced category \(expectedArticle.categoryId) should exist")
            } else {
                Issue.record("Article \(expectedArticle.id) should exist after sync")
            }
        }
    }
    
    // MARK: - Coordinated SoftSync Tests (Simulating Multi-Model Behavior)
    
    @Test("Coordinated softSync establishes proper relationships")
    func testCoordinatedSoftSyncEstablishesRelationships() async throws {
        let orm = try await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Create related data with proper foreign key relationships
        let authors = [
            Author(id: 1, name: "Alice Smith", email: "alice@example.com", bio: "Tech writer"),
            Author(id: 2, name: "Bob Johnson", email: "bob@example.com", bio: "Science journalist")
        ]
        
        let categories = [
            Category(id: 1, name: "Technology", description: "Tech articles", color: "blue"),
            Category(id: 2, name: "Science", description: "Science articles", color: "green")
        ]
        
        let articles = [
            Article(id: 1, title: "Introduction to Swift", content: "Swift basics...", authorId: 1, categoryId: 1, isPublished: true),
            Article(id: 2, title: "Physics Explained", content: "Physics concepts...", authorId: 2, categoryId: 2, isPublished: true),
            Article(id: 3, title: "Advanced Swift", content: "Advanced topics...", authorId: 1, categoryId: 1, isPublished: false)
        ]
        
        // Perform coordinated softSync in dependency order (parents before children)
        
        // 1. Sync authors first (no dependencies)
        let authorResult = await Author.softSync(with: authors, orm: orm)
        switch authorResult {
        case .success(let changes):
            #expect(changes.inserted.count == 2, "Should insert 2 authors")
            #expect(changes.updated.count == 0, "Should update 0 authors")
        case .failure(let error):
            Issue.record("Author softSync failed: \(error)")
        }
        
        // 2. Sync categories (no dependencies)
        let categoryResult = await Category.softSync(with: categories, orm: orm)
        switch categoryResult {
        case .success(let changes):
            #expect(changes.inserted.count == 2, "Should insert 2 categories")
        case .failure(let error):
            Issue.record("Category softSync failed: \(error)")
        }
        
        // 3. Sync articles (depends on authors and categories)
        let articleResult = await Article.softSync(with: articles, orm: orm)
        switch articleResult {
        case .success(let changes):
            #expect(changes.inserted.count == 3, "Should insert 3 articles")
        case .failure(let error):
            Issue.record("Article softSync failed: \(error)")
        }
        
        // Verify relationships are properly established
        await verifyRelationshipIntegrity(orm: orm, expectedAuthors: authors, expectedCategories: categories, expectedArticles: articles)
    }
    
    @Test("Coordinated softSync preserves existing relationships during updates")
    func testCoordinatedSoftSyncPreservesExistingRelationships() async throws {
        let orm = try await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let authorRepo = await orm.repository(for: Author.self)
        let categoryRepo = await orm.repository(for: Category.self)
        let articleRepo = await orm.repository(for: Article.self)
        
        // Pre-insert some data with relationships
        var existingAuthor = Author(id: 1, name: "Local Author", email: "local@example.com", bio: "Local writer")
        var existingCategory = Category(id: 1, name: "Local Category", description: "Local content", color: "red")
        var existingArticle = Article(id: 1, title: "Local Article", content: "Local content...", authorId: 1, categoryId: 1, isPublished: false)
        
        _ = await authorRepo.insert(&existingAuthor)
        _ = await categoryRepo.insert(&existingCategory)
        _ = await articleRepo.insert(&existingArticle)
        
        // Server data: update existing + add new with relationships
        let serverAuthors = [
            Author(id: 1, name: "Updated Author", email: "updated@example.com", bio: "Updated bio"), // Update existing
            Author(id: 2, name: "New Author", email: "new@example.com", bio: "New writer") // Insert new
        ]
        
        let serverCategories = [
            Category(id: 1, name: "Updated Category", description: "Updated desc", color: "purple"), // Update existing
            Category(id: 2, name: "New Category", description: "New category", color: "orange") // Insert new
        ]
        
        let serverArticles = [
            Article(id: 1, title: "Updated Article", content: "Updated content...", authorId: 1, categoryId: 1, isPublished: true), // Update existing with same relationships
            Article(id: 2, title: "New Article", content: "New content...", authorId: 2, categoryId: 2, isPublished: true), // Insert new with new relationships
            Article(id: 3, title: "Cross Article", content: "Cross content...", authorId: 1, categoryId: 2, isPublished: false) // Insert with mixed relationships
        ]
        
        // Perform coordinated softSync (updating existing relationships)
        
        // 1. Update authors
        let authorResult = await Author.softSync(with: serverAuthors, orm: orm)
        switch authorResult {
        case .success(let changes):
            #expect(changes.inserted.count == 1, "Should insert 1 new author")
            #expect(changes.updated.count == 1, "Should update 1 existing author")
        case .failure(let error):
            Issue.record("Author softSync failed: \(error)")
        }
        
        // 2. Update categories
        let categoryResult = await Category.softSync(with: serverCategories, orm: orm)
        switch categoryResult {
        case .success(let changes):
            #expect(changes.inserted.count == 1, "Should insert 1 new category")
            #expect(changes.updated.count == 1, "Should update 1 existing category")
        case .failure(let error):
            Issue.record("Category softSync failed: \(error)")
        }
        
        // 3. Update articles (relationships should still be valid)
        let articleResult = await Article.softSync(with: serverArticles, orm: orm)
        switch articleResult {
        case .success(let changes):
            #expect(changes.inserted.count == 2, "Should insert 2 new articles")
            #expect(changes.updated.count == 1, "Should update 1 existing article")
        case .failure(let error):
            Issue.record("Article softSync failed: \(error)")
        }
        
        // Verify relationships are correctly maintained
        await verifyRelationshipIntegrity(orm: orm, expectedAuthors: serverAuthors, expectedCategories: serverCategories, expectedArticles: serverArticles)
        
        // Verify cross-relationships work (author 1 with category 2)
        let crossArticleResult = await articleRepo.find(id: 3)
        if case .success(let crossArticle) = crossArticleResult {
            #expect(crossArticle?.authorId == 1, "Cross article should reference author 1")
            #expect(crossArticle?.categoryId == 2, "Cross article should reference category 2")
        } else {
            Issue.record("Cross article should exist")
        }
    }
    
    @Test("Coordinated softSync handles relationship changes correctly")
    func testCoordinatedSoftSyncHandlesRelationshipChanges() async throws {
        let orm = try await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let authorRepo = await orm.repository(for: Author.self)
        let categoryRepo = await orm.repository(for: Category.self)
        let articleRepo = await orm.repository(for: Article.self)
        
        // Pre-insert local data with original relationships
        var localAuthor = Author(id: 1, name: "Local Author", email: "local@example.com", bio: "Local bio")
        var localCategory = Category(id: 1, name: "Local Category", description: "Local desc", color: "local")
        var localArticle = Article(id: 1, title: "Local Article", content: "Local content", authorId: 1, categoryId: 1, isPublished: false)
        
        _ = await authorRepo.insert(&localAuthor)
        _ = await categoryRepo.insert(&localCategory)
        _ = await articleRepo.insert(&localArticle)
        
        // Server data with NEW entities and CHANGED relationships
        let serverAuthors = [
            Author(id: 1, name: "Server Author", email: "server@example.com", bio: "Server bio"), // Same ID, different data
            Author(id: 2, name: "New Server Author", email: "new.server@example.com", bio: "New server bio")
        ]
        
        let serverCategories = [
            Category(id: 1, name: "Server Category", description: "Server desc", color: "server"), // Same ID, different data
            Category(id: 2, name: "New Server Category", description: "New server desc", color: "new.server")
        ]
        
        let serverArticles = [
            Article(id: 1, title: "Server Article", content: "Server content", authorId: 2, categoryId: 2, isPublished: true), // Same ID, CHANGED relationships!
            Article(id: 2, title: "New Server Article", content: "New server content", authorId: 1, categoryId: 1, isPublished: true)
        ]
        
        // Perform coordinated softSync with server wins strategy
        
        // 1. Sync authors first (dependencies first)
        let authorResult = await Author.softSync(with: serverAuthors, orm: orm, conflictResolution: .serverWins)
        switch authorResult {
        case .success(let changes):
            #expect(changes.inserted.count == 1, "Should insert 1 new author")
            #expect(changes.updated.count == 1, "Should update 1 existing author")
        case .failure(let error):
            Issue.record("Author softSync failed: \(error)")
        }
        
        // 2. Sync categories
        let categoryResult = await Category.softSync(with: serverCategories, orm: orm, conflictResolution: .serverWins)
        switch categoryResult {
        case .success(let changes):
            #expect(changes.inserted.count == 1, "Should insert 1 new category")
            #expect(changes.updated.count == 1, "Should update 1 existing category")
        case .failure(let error):
            Issue.record("Category softSync failed: \(error)")
        }
        
        // 3. Sync articles (relationships should be updated)
        let articleResult = await Article.softSync(with: serverArticles, orm: orm, conflictResolution: .serverWins)
        switch articleResult {
        case .success(let changes):
            #expect(changes.inserted.count == 1, "Should insert 1 new article")
            #expect(changes.updated.count == 1, "Should update 1 existing article")
        case .failure(let error):
            Issue.record("Article softSync failed: \(error)")
        }
        
        // Verify article 1 now has NEW relationships (authorId: 2, categoryId: 2)
        let updatedArticleResult = await articleRepo.find(id: 1)
        if case .success(let updatedArticle) = updatedArticleResult {
            #expect(updatedArticle?.authorId == 2, "Article 1 should now reference author 2 (server wins)")
            #expect(updatedArticle?.categoryId == 2, "Article 1 should now reference category 2 (server wins)")
            #expect(updatedArticle?.title == "Server Article", "Article 1 should have server title")
            #expect(updatedArticle?.isPublished == true, "Article 1 should be published (server data)")
            
            // Verify the new relationships are valid
            let newAuthorResult = await authorRepo.find(id: 2)
            #expect(newAuthorResult.isSuccess, "New author 2 should exist for relationship")
            
            let newCategoryResult = await categoryRepo.find(id: 2)
            #expect(newCategoryResult.isSuccess, "New category 2 should exist for relationship")
        } else {
            Issue.record("Updated article should be findable")
        }
    }
    
    @Test("Coordinated softSync handles deep relationship dependencies")
    func testCoordinatedSoftSyncDeepRelationshipDependencies() async throws {
        let orm = try await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Create complex data with multiple levels of relationships
        let authors = [
            Author(id: 1, name: "John Doe", email: "john@example.com", bio: "Senior writer"),
            Author(id: 2, name: "Jane Smith", email: "jane@example.com", bio: "Editor")
        ]
        
        let categories = [
            Category(id: 1, name: "Programming", description: "Programming tutorials", color: "blue"),
            Category(id: 2, name: "Design", description: "UI/UX design", color: "purple")
        ]
        
        let articles = [
            Article(id: 1, title: "Swift Fundamentals", content: "Learn Swift...", authorId: 1, categoryId: 1, isPublished: true),
            Article(id: 2, title: "iOS Design Patterns", content: "Design patterns...", authorId: 1, categoryId: 2, isPublished: true)
        ]
        
        let comments = [
            Comment(id: 1, content: "Great article!", authorId: 2, articleId: 1, isApproved: true),
            Comment(id: 2, content: "Very helpful", authorId: 1, articleId: 2, isApproved: true),
            Comment(id: 3, content: "Need more examples", authorId: 2, articleId: 1, isApproved: false)
        ]
        
        // Sync in dependency order: Authors -> Categories -> Articles -> Comments
        
        // 1. Authors (no dependencies)
        let authorResult = await Author.softSync(with: authors, orm: orm)
        switch authorResult {
        case .success(let changes):
            #expect(changes.inserted.count == 2, "Should insert 2 authors")
        case .failure(let error):
            Issue.record("Author softSync failed: \(error)")
        }
        
        // 2. Categories (no dependencies)
        let categoryResult = await Category.softSync(with: categories, orm: orm)
        switch categoryResult {
        case .success(let changes):
            #expect(changes.inserted.count == 2, "Should insert 2 categories")
        case .failure(let error):
            Issue.record("Category softSync failed: \(error)")
        }
        
        // 3. Articles (depends on authors and categories)
        let articleResult = await Article.softSync(with: articles, orm: orm)
        switch articleResult {
        case .success(let changes):
            #expect(changes.inserted.count == 2, "Should insert 2 articles")
        case .failure(let error):
            Issue.record("Article softSync failed: \(error)")
        }
        
        // 4. Comments (depends on authors and articles)
        let commentResult = await Comment.softSync(with: comments, orm: orm)
        switch commentResult {
        case .success(let changes):
            #expect(changes.inserted.count == 3, "Should insert 3 comments")
        case .failure(let error):
            Issue.record("Comment softSync failed: \(error)")
        }
        
        // Verify complex relationships
        let commentRepo = await orm.repository(for: Comment.self)
        let allCommentsResult = await commentRepo.findAll()
        
        if case .success(let allComments) = allCommentsResult {
            // Verify comments reference valid authors and articles
            for comment in allComments {
                let authorRepo = await orm.repository(for: Author.self)
                let authorResult = await authorRepo.find(id: comment.authorId)
                #expect(authorResult.isSuccess, "Comment \(comment.id) should reference valid author \(comment.authorId)")
                
                let articleRepo = await orm.repository(for: Article.self)
                let articleResult = await articleRepo.find(id: comment.articleId)
                #expect(articleResult.isSuccess, "Comment \(comment.id) should reference valid article \(comment.articleId)")
            }
        } else {
            Issue.record("Should be able to fetch all comments")
        }
        
        // Verify transitive relationships (comments -> articles -> authors/categories)
        if case .success(let allComments) = allCommentsResult {
            for comment in allComments {
                let articleRepo = await orm.repository(for: Article.self)
                let articleResult = await articleRepo.find(id: comment.articleId)
                
                if case .success(let article) = articleResult, let article = article {
                    // Verify article's author exists
                    let authorRepo = await orm.repository(for: Author.self)
                    let articleAuthorResult = await authorRepo.find(id: article.authorId)
                    #expect(articleAuthorResult.isSuccess, "Article \(article.id) should reference valid author \(article.authorId)")
                    
                    // Verify article's category exists
                    let categoryRepo = await orm.repository(for: Category.self)
                    let articleCategoryResult = await categoryRepo.find(id: article.categoryId)
                    #expect(articleCategoryResult.isSuccess, "Article \(article.id) should reference valid category \(article.categoryId)")
                }
            }
        }
    }
    
    @Test("softSync preserves local-only data with relationships")
    func testSoftSyncPreservesLocalOnlyDataWithRelationships() async throws {
        let orm = try await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let authorRepo = await orm.repository(for: Author.self)
        let categoryRepo = await orm.repository(for: Category.self)
        let articleRepo = await orm.repository(for: Article.self)
        
        // Create local-only author and category
        var localAuthor = Author(id: 100, name: "Local Only Author", email: "local@example.com", bio: "Local writer")
        var localCategory = Category(id: 100, name: "Local Only Category", description: "Local category", color: "local")
        var localArticle = Article(id: 100, title: "Local Only Article", content: "Local content", authorId: 100, categoryId: 100, isPublished: false)
        
        _ = await authorRepo.insert(&localAuthor)
        _ = await categoryRepo.insert(&localCategory)
        _ = await articleRepo.insert(&localArticle)
        
        // Server data (does NOT include local-only items)
        let serverAuthors = [
            Author(id: 1, name: "Server Author", email: "server@example.com", bio: "Server writer")
        ]
        
        let serverCategories = [
            Category(id: 1, name: "Server Category", description: "Server category", color: "server")
        ]
        
        let serverArticles = [
            Article(id: 1, title: "Server Article", content: "Server content", authorId: 1, categoryId: 1, isPublished: true)
        ]
        
        // Perform softSync - should add server data but preserve local-only data
        _ = await Author.softSync(with: serverAuthors, orm: orm)
        _ = await Category.softSync(with: serverCategories, orm: orm)
        _ = await Article.softSync(with: serverArticles, orm: orm)
        
        // Verify local-only data still exists
        let localAuthorResult = await authorRepo.find(id: 100)
        #expect(localAuthorResult.isSuccess, "Local-only author should still exist")
        
        let localCategoryResult = await categoryRepo.find(id: 100)
        #expect(localCategoryResult.isSuccess, "Local-only category should still exist")
        
        let localArticleResult = await articleRepo.find(id: 100)
        #expect(localArticleResult.isSuccess, "Local-only article should still exist")
        
        // Verify local-only relationships are still intact
        if case .success(let localArticleData) = localArticleResult, let localArticleData = localArticleData {
            #expect(localArticleData.authorId == 100, "Local article should still reference local author")
            #expect(localArticleData.categoryId == 100, "Local article should still reference local category")
        }
        
        // Verify server data was also added
        let serverAuthorResult = await authorRepo.find(id: 1)
        #expect(serverAuthorResult.isSuccess, "Server author should exist")
        
        let serverArticleResult = await articleRepo.find(id: 1)
        #expect(serverArticleResult.isSuccess, "Server article should exist")
        
        // Verify total counts (local + server)
        let allAuthorsResult = await authorRepo.findAll()
        if case .success(let allAuthors) = allAuthorsResult {
            #expect(allAuthors.count == 2, "Should have 2 authors total (1 local + 1 server)")
        }
        
        let allArticlesResult = await articleRepo.findAll()
        if case .success(let allArticles) = allArticlesResult {
            #expect(allArticles.count == 2, "Should have 2 articles total (1 local + 1 server)")
        }
    }
}