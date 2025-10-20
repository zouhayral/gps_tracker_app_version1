# GPS Tracker - Flutter Application

A production-ready GPS tracking application built with Flutter, featuring real-time vehicle tracking, map visualization, and notification systems. Integrates with Traccar API for fleet management.

## 🚀 Features

- **Real-time Tracking:** WebSocket-based live position updates
- **Interactive Map:** FlutterMap with FMTC tile caching (OSM + Satellite)
- **Smart Markers:** Isolate-based clustering for 800+ devices
- **Smooth Animation:** Marker motion controller with cubic easing
- **Offline Support:** FMTC tile caching with dual stores
- **Multi-Customer:** Customer session management with typed WebSocket messages
- **Notifications:** Event tracking system (in progress)

## 📚 Documentation

### Quick Start
→ **[docs/ARCHITECTURE_SUMMARY.md](docs/ARCHITECTURE_SUMMARY.md)** - Get up to speed in 5 minutes

### Complete Documentation
→ **[docs/00_ARCHITECTURE_INDEX.md](docs/00_ARCHITECTURE_INDEX.md)** - Full documentation index

### Key Documents
- **[Architecture Analysis](docs/ARCHITECTURE_ANALYSIS.md)** - Complete architectural deep-dive
- **[Visual Diagrams](docs/ARCHITECTURE_VISUAL_DIAGRAMS.md)** - Data flow diagrams
- **[Notification Implementation](docs/NOTIFICATION_SYSTEM_IMPLEMENTATION.md)** - Step-by-step guide
- **[Project Overview](docs/PROJECT_OVERVIEW_AI_BASE.md)** - Core stack summary

## 🏗️ Architecture

**Type:** Hybrid (Feature-First + Repository Pattern + Clean Architecture)

```
UI Layer (Features) → Riverpod Providers → Repository → Services → Persistence
```

**Stack:**
- Flutter (multi-platform)
- Riverpod 2.x (state management)
- ObjectBox (local persistence)
- FMTC v10 (tile caching)
- Dio + WebSocket (networking)
- flutter_map 8.x (map engine)

## 🛠️ Getting Started

### Prerequisites
- Flutter SDK (latest stable)
- Dart SDK (bundled with Flutter)
- Android Studio / Xcode (for mobile)
- Traccar server instance

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd my_app_gps_version1
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate ObjectBox code** (if needed)
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Run the app**
   ```bash
   flutter run
   ```

### Configuration

Configure your Traccar server URL in the appropriate service configuration files.

## 📁 Project Structure

```
lib/
├── core/              # Shared infrastructure
├── data/              # Models + repositories
├── domain/            # Entities + use cases
├── features/          # Feature modules
│   ├── auth/          # Authentication
│   ├── map/           # Map & tracking
│   ├── dashboard/     # Device dashboard
│   └── notifications/ # Notifications (in progress)
├── providers/         # App-wide Riverpod providers
├── services/          # Business logic services
└── widgets/           # Reusable widgets
```

## 🧪 Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Analyze code
flutter analyze
```

## 🎯 Performance Highlights

- ✅ Isolate-based marker clustering (800+ markers)
- ✅ LRU badge cache (73% hit rate)
- ✅ Motion interpolation (5 FPS, cubic easing)
- ✅ FMTC dual-store tile caching
- ✅ Debounced updates (prevent UI flooding)

## 🔄 Current Status

- ✅ **Core Features:** Production-ready
- ✅ **Map System:** Highly optimized
- ✅ **WebSocket:** Real-time updates working
- ⚠️ **Notifications:** Infrastructure ready, UI in progress

## 🤝 Contributing

1. Read [Architecture Documentation](docs/00_ARCHITECTURE_INDEX.md)
2. Follow established patterns
3. Write tests for new features
4. Update documentation when adding features

## 📝 License

[Add your license here]

## 🙏 Acknowledgments

- [flutter_map](https://pub.dev/packages/flutter_map) - Map rendering
- [Riverpod](https://pub.dev/packages/flutter_riverpod) - State management
- [ObjectBox](https://pub.dev/packages/objectbox) - Local database
- [FMTC](https://pub.dev/packages/flutter_map_tile_caching) - Tile caching
- [Traccar](https://www.traccar.org/) - GPS tracking platform
