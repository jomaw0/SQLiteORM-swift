# Shopping List App with SQLiteORM-swift

A comprehensive SwiftUI shopping list application demonstrating local storage with SQLiteORM-swift, CRUD operations, relationships, and reactive UI updates using Combine.

## 📋 Features

- **Multiple Shopping Lists**: Create, edit, and delete shopping lists
- **Shopping Items**: Add items with name, quantity, price, category, and notes
- **Real-time Updates**: Checked items update instantly across the app
- **Progress Tracking**: Visual progress indicators showing completion status
- **Cost Calculation**: Automatic total and purchased cost calculations
- **Category Organization**: Items organized by categories
- **Search Functionality**: Search items within lists
- **Coordinator Pattern**: Clean navigation architecture
- **Combine Integration**: Reactive programming for UI updates

## 🏗️ Architecture

### Project Structure

```
ShoppingListApp/
├── App/
│   ├── ShoppingListApp.swift          # App entry point
│   └── AppCoordinator.swift           # Main app coordinator
├── Models/
│   ├── ShoppingList.swift             # Shopping list entity
│   ├── ShoppingItem.swift             # Shopping item entity
│   └── DatabaseManager.swift         # SQLiteORM database wrapper
├── ViewModels/
│   ├── ShoppingListsViewModel.swift   # Lists overview view model
│   ├── ShoppingItemsViewModel.swift   # Items detail view model
│   └── AddEditViewModel.swift         # Add/Edit forms view model
├── Views/
│   ├── ShoppingListsView.swift        # Lists overview tab
│   ├── ShoppingItemsView.swift        # Items detail view
│   ├── AddEditListView.swift          # Add/Edit list form
│   ├── AddEditItemView.swift          # Add/Edit item form
│   └── Components/
│       ├── ListRowView.swift          # List row component
│       ├── ItemRowView.swift          # Item row component
│       └── ProgressView.swift         # Custom progress indicator
├── Coordinators/
│   ├── Coordinator.swift              # Base coordinator protocol
│   ├── ShoppingCoordinator.swift      # Shopping flow coordinator
│   └── NavigationCoordinator.swift    # Navigation wrapper
└── Extensions/
    ├── Publisher+Extensions.swift     # Combine helpers
    └── View+Extensions.swift          # SwiftUI helpers
```

### Key Architectural Patterns

#### 1. **Coordinator Pattern**
- **AppCoordinator**: Manages the main TabView and coordinates between different flows
- **ShoppingCoordinator**: Handles navigation within the shopping list flow
- **NavigationCoordinator**: Generic wrapper for SwiftUI navigation

#### 2. **MVVM with Combine**
- **ViewModels**: Handle business logic and state management
- **Publishers**: Emit data changes using @Published properties
- **Subscribers**: Views automatically update when data changes

#### 3. **Repository Pattern**
- **DatabaseManager**: Abstracts SQLiteORM operations
- **Entity Models**: Direct SQLiteORM entity mappings
- **Service Layer**: Business logic for data operations

## 🗄️ Database Schema

### ShoppingList Entity
```swift
@ORMTable
struct ShoppingList: ORMTable {
    typealias IDType = Int
    
    var id: Int = 0
    var name: String
    var createdAt: Date
    var isActive: Bool = true
    
    // Computed properties for UI (not stored in DB)
    var totalItems: Int = 0
    var checkedItems: Int = 0
    var totalCost: Double = 0.0
    var purchasedCost: Double = 0.0
    
    var completionPercentage: Double {
        guard totalItems > 0 else { return 0 }
        return Double(checkedItems) / Double(totalItems) * 100
    }
}
```

### ShoppingItem Entity
```swift
@ORMTable
struct ShoppingItem: ORMTable {
    typealias IDType = Int
    
    var id: Int = 0
    var listId: Int
    var name: String
    var quantity: Int = 1
    var price: Double = 0.0
    var isChecked: Bool = false
    var category: String = "Other"
    var notes: String = ""
    var addedAt: Date
    
    var totalPrice: Double {
        return price * Double(quantity)
    }
}
```

## 🔄 Data Flow

### 1. **Database Operations**
```swift
// DatabaseManager handles all SQLiteORM operations
@MainActor
class DatabaseManager: ObservableObject {
    private var orm: ORM?
    private var listRepository: Repository<ShoppingList>?
    private var itemRepository: Repository<ShoppingItem>?
    
    func setupDatabase() async {
        orm = ORM(path: "shopping_lists.sqlite")
        await orm?.open()
        
        listRepository = await orm?.repository(for: ShoppingList.self)
        itemRepository = await orm?.repository(for: ShoppingItem.self)
        
        _ = await listRepository?.createTable()
        _ = await itemRepository?.createTable()
    }
    
    // CRUD Operations using Result types
    func createList(name: String) async {
        var list = ShoppingList(name: name)
        let result = await listRepository?.insert(&list)
        // Handle result
    }
    
    func fetchLists() async -> [ShoppingList] {
        let result = await listRepository?.findAll()
        switch result {
        case .success(let lists):
            return lists
        case .failure(let error):
            print("Error: \(error)")
            return []
        case .none:
            return []
        }
    }
}
```

### 2. **ViewModel Pattern**
```swift
@MainActor
class ShoppingListsViewModel: ObservableObject {
    @Published var searchText = ""
    
    private let databaseManager: DatabaseManager
    
    // Reactive updates through DatabaseManager's @Published properties
    var filteredLists: [ShoppingList] {
        let lists = databaseManager.shoppingLists
        if searchText.isEmpty {
            return lists
        } else {
            return lists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    func createList(name: String) async {
        await databaseManager.createList(name: name)
    }
}
```

### 3. **Coordinator Navigation**
```swift
class ShoppingCoordinator: ObservableObject {
    @Published var path = NavigationPath()
    @Published var sheet: SheetDestination?
    @Published var alert: AlertDestination?
    
    enum Destination {
        case listDetail(ShoppingList)
        case addEditList(ShoppingList?)
        case addEditItem(ShoppingList, ShoppingItem?)
    }
    
    func navigate(to destination: Destination) {
        // Handle navigation logic
    }
}
```

## 🎨 UI Components

### 1. **TabView Structure**
```swift
TabView {
    NavigationStack(path: $coordinator.listsPath) {
        ShoppingListsView()
            .navigationDestination(for: ShoppingCoordinator.Destination.self) { destination in
                // Route to appropriate view
            }
    }
    .tabItem { Label("Lists", systemImage: "list.bullet") }
    
    SettingsView()
        .tabItem { Label("Settings", systemImage: "gear") }
}
```

### 2. **Reactive List Updates**
```swift
struct ShoppingListsView: View {
    @StateObject private var viewModel = ShoppingListsViewModel()
    @EnvironmentObject private var coordinator: ShoppingCoordinator
    
    var body: some View {
        List(viewModel.shoppingLists) { list in
            ListRowView(list: list)
                .onTapGesture {
                    coordinator.navigate(to: .listDetail(list))
                }
        }
        .onReceive(viewModel.$shoppingLists) { lists in
            // React to list changes
        }
    }
}
```

### 3. **Custom Progress Components**
```swift
struct ProgressView: View {
    let totalItems: Int
    let checkedItems: Int
    
    private var progress: Double {
        guard totalItems > 0 else { return 0 }
        return Double(checkedItems) / Double(totalItems)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("\(checkedItems) of \(totalItems) completed")
                Spacer()
                Text("\(Int(progress * 100))%")
            }
            
            ProgressBar(value: progress)
        }
    }
}
```

## 🔧 Combine Integration

### 1. **Built-in Subscriptions**
```swift
@MainActor
class DatabaseManager: ObservableObject {
    @Published var shoppingLists: [ShoppingList] = []
    @Published var allItems: [ShoppingItem] = []
    
    // Combine subscriptions using SQLiteORM's subscribe methods
    private var listSubscription: SimpleQuerySubscription<ShoppingList>?
    private var itemSubscription: SimpleQuerySubscription<ShoppingItem>?
    private var cancellables = Set<AnyCancellable>()
    
    private func setupSubscriptions() async {
        guard let listRepository = listRepository,
              let itemRepository = itemRepository else { return }
        
        // Subscribe to all lists
        listSubscription = await listRepository.subscribe()
        listSubscription?.$result
            .compactMap { result -> [ShoppingList]? in
                if case .success(let lists) = result {
                    return lists
                }
                return nil
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.shoppingLists, on: self)
            .store(in: &cancellables)
    }
}
```

### 2. **Query-based Subscriptions**
```swift
// Subscribe to filtered data
let activeListsSubscription = await listRepository.subscribe(
    query: ORMQueryBuilder<ShoppingList>().where("isActive", .equal, true)
)

// Subscribe to items for a specific list
let itemsQuery = ORMQueryBuilder<ShoppingItem>()
    .where("listId", .equal, listId)
    .orderBy("isChecked", ascending: true)

let itemsSubscription = await itemRepository.subscribe(query: itemsQuery)
```
```

## 📱 User Experience Features

### 1. **Real-time Updates**
- Items check/uncheck instantly updates progress bars
- Cost calculations update automatically
- List completion percentages update in real-time

### 2. **Smooth Navigation**
- Coordinator pattern ensures clean navigation stack
- Sheet presentations for forms
- Alert confirmations for destructive actions

### 3. **Search and Filter**
- Search items within lists
- Filter by category
- Filter by completion status

### 4. **Visual Feedback**
- Loading states during database operations
- Error handling with user-friendly messages
- Success animations for completed actions

## 🚀 Getting Started

### Dependencies
This example uses the local SQLiteORM package. In Xcode:
1. Add the local SQLiteORM package to your project
2. Import SQLiteORM in your Swift files:
```swift
import SQLiteORM
```

### Database Setup
```swift
// In App initialization
let databaseManager = DatabaseManager()
databaseManager.setupDatabase()
```

### Key Implementation Points

1. **Entity Relationships**: Use `@ForeignKey` for list-item relationships
2. **Combine Publishers**: Emit changes through NotificationCenter
3. **Coordinator Navigation**: Handle all navigation through coordinators
4. **Reactive UI**: Use `@Published` properties for automatic UI updates
5. **Error Handling**: Implement proper error handling for database operations

This architecture provides a scalable, maintainable SwiftUI app with proper separation of concerns, reactive programming, and clean navigation patterns.
