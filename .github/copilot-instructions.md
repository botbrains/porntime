# Copilot Instructions for PopcornTimeTV

## Project Overview

PopcornTimeTV is an iOS and tvOS application for streaming torrented movies and TV shows. The codebase is organized into two main targets:
- **PopcornTimeiOS**: iPhone and iPad application (minimum iOS 13)
- **PopcornTimetvOS**: Apple TV application (minimum tvOS 13)

Both share code through **PopcornKit**, a framework containing all business logic, API managers, and data models.

## Architecture

### Three-Layer Structure

1. **PopcornKit Framework** (`PopcornKit/`): Platform-agnostic business logic
   - **Managers**: API interactions (ShowManager, MovieManager, TraktManager, PopcornTorrent)
   - **Models**: Data structures (Show, Movie, Episode, Actor, Torrent, etc.) conforming to `ObjectMapper` for JSON serialization
   - **Resources**: Utilities (subtitle hashing, HTML decoding, OAuth handling)
   - **Trakt**: Trakt.tv authentication and API integration

2. **PopcornTime App** (`PopcornTime/`): Shared UI components and platform-specific implementations
   - **UI/Shared**: Common view controllers (PlayerViewController, DetailViewController, ItemViewController)
   - **UI/iOS**: iPhone/iPad-specific UI (cell designs, layouts)
   - **UI/tvOS**: Apple TV-specific UI (focus engine, tvOS gestures)
   - **Extensions**: Platform-agnostic extensions (String, Date, etc.)
   - **Startup**: AppDelegate and initial setup

3. **TopShelf** (`TopShelf/`): Apple TV Top Shelf app extension for featured content

### Data Flow

- **API Managers** (PopcornKit) fetch and parse JSON into model objects using ObjectMapper
- **Models** implement the `Media` protocol (shared interface for Movie and Show)
- **View Controllers** consume models and managers, with platform-specific UI implementations
- **Downloads** are managed by PopcornTorrent via PopcornKit

## Build & Dependency Management

### Setup

```bash
# Install Ruby dependencies and CocoaPods
gem install bundler
bundle install
bundle exec pod repo update
bundle exec pod install

# Open the workspace (NOT the .xcodeproj file)
open PopcornTime.xcworkspace
```

### Key Dependencies

- **PopcornTorrent** (v1.3.0): Torrent handling and streaming
- **Alamofire** (v4.9.0): HTTP networking
- **ObjectMapper** (v3.5.0): JSON serialization
- **MobileVLCKit** (v3.3.0, iOS) / **TVVLCKit** (v3.3.0, tvOS): Video playback
- **Trakt Integration**: Custom pod from PopcornTimeTV/Specs for authentication

### Build Schemes

Three main schemes are available in Xcode:
- `PopcornTimeiOS`: Build iOS app
- `PopcornTimetvOS`: Build tvOS app
- `TopShelf`: Build tvOS Top Shelf extension

## Testing

Tests are minimal and serve as templates. To run:

```bash
# Run all tests
xcodebuild test -workspace PopcornTime.xcworkspace -scheme PopcornTimeiOS

# Run specific test class
xcodebuild test -workspace PopcornTime.xcworkspace -scheme PopcornTimeiOS -only-testing PopcornTimeiOSTests/YourTestClass
```

Test targets exist for iOS, tvOS, and UI tests but contain only example test cases.

## Code Style & Conventions

### Swift Style Guide

- **No `self` prefix** unless inside closures
- **No `init` keyword** when initializing
- **Opening brace on same line** as function declaration:
  ```swift
  func myFunction(var: String) {
      // code
  }
  ```

- **Avoid semaphores** and use DispatchQueue/async patterns instead

### Documentation

**All public APIs must include markup documentation:**

```swift
/**
    Brief description of what this does.
    
    - Parameter name: Explanation of parameter.
    
    - Returns: What is returned.
    
    - Important: Any critical information.
*/
```

### Code Organization

- Use `// MARK:` comments to organize code sections
- Models use enums for constants (e.g., filter types, API endpoints)
- Managers are singletons (accessed via `.shared`)
- Conditional compilation (`#if os(tvOS)`) separates platform-specific UI logic

## Key Manager APIs (PopcornKit Public Interface)

All public functions are wrappers around manager singletons:

```swift
// Shows
loadShows(page:filterBy:genre:searchTerm:orderBy:completion:)
getShowInfo(imdbId:completion:)

// Movies
loadMovies(page:filterBy:genre:searchTerm:orderBy:completion:)
getMovieInfo(imdbId:completion:)

// Generic
getWatchedList(mediaType:completion:)
searchMedia(query:type:completion:)
```

Parameters accept filter/genre/order enums (e.g., `ShowManager.Filters`, `ShowManager.Genres`).

## Model Patterns

**Media Protocol**: Shared interface for Movie and Show
- `id`, `title`, `year`, `rating`, `runtime`, etc.
- Conformance required for generic handling in UI

**ObjectMapper Integration**: All models conform to `Mappable` for JSON parsing
- Use `MARK: Mappable` section for mapping logic
- Handle optional chaining for missing fields gracefully

**Associated Relationships**:
- Show → Episodes (populated via ShowManager)
- Movie/Episode → Torrents (embedded in JSON)
- Media → Downloads (assigned dynamically)

## Platform-Specific Notes

### iOS

- Uses standard UIViewController/UICollectionViewController patterns
- Supports iPhone and iPad layouts
- Chromecast integration via google-cast-sdk
- 1Password extension support

### tvOS

- Leverages focus engine for navigation (no pointer/cursor)
- Custom button implementations (`TVButton`) for focus styling
- `isDark` property toggles UI color schemes
- `TvOSMoreButton` for overflow menus

## Localization

Multiple `.lproj` folders provide translations:
- `ar.lproj` (Arabic), `es.lproj` (Spanish), `fr.lproj` (French), `it.lproj` (Italian), `nl-NL.lproj` (Dutch), `pt-BR.lproj` (Portuguese)
- Strings are maintained in Localizable.strings files
- Contributions welcome via the [Translating Guide](https://github.com/PopcornTimeTV/PopcornTimeTV/wiki/Translating-Popcorn-Time)

## Common Tasks

### Adding a New API Endpoint

1. Create a method in the appropriate Manager class (ShowManager, MovieManager, etc.) in PopcornKit
2. Wrap it in a public function in PopcornKit.swift
3. Use Alamofire for HTTP requests
4. Parse JSON responses using ObjectMapper

### Adding UI for a New Feature

1. Create platform-agnostic logic in a Shared view controller
2. Add platform-specific overrides in iOS/tvOS folders
3. Use conditional compilation (`#if os(tvOS)`) for inline platform differences
4. Ensure tvOS version accounts for focus engine and remote gestures

### Handling Model Updates

1. Add properties to the Model struct
2. Implement mapping in the `Mappable` section
3. Update managers that populate that model
4. Update any UI that displays the property

## Important Considerations

- Always use the **workspace** (`PopcornTime.xcworkspace`), not the project file
- Models are structs, not classes—think immutability and value semantics
- Async operations use DispatchQueue; avoid semaphores
- Pod installation required after Podfile changes: `bundle exec pod install`
- tvOS UI requires special attention to focus and remote navigation patterns
- Trakt authentication state is handled in PopcornKit; check OAuthCredential for token management

## MCP Servers

The following MCP servers enhance the Copilot experience for this project:

### Xcode Integration
Provides code navigation, symbol search, and build system introspection for Swift files:
- Navigate to symbol definitions across PopcornKit and PopcornTime targets
- Find usages of managers, models, and view controllers
- Query build configurations and schemes

Configuration: Connect to Xcode's LSP for Swift via MCP Xcode integration

### CocoaPods Build Tools
Automates dependency management and build tasks:
- View Podfile structure and dependency versions
- Run `bundle exec pod install` and `pod repo update` via MCP
- Query installed pod versions and specifications

Configuration: MCP CocoaPods server for dependency and build automation
