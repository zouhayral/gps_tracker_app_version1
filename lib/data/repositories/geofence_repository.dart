import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/geofences_dao.dart';
import 'package:my_app_gps/data/models/geofence.dart';

/// Repository for managing geofences with offline-first architecture.
///
/// Responsibilities:
/// - Provide stream of geofences for UI (real-time updates)
/// - Manage local ObjectBox persistence via GeofencesDAO
/// - Handle CRUD operations with caching
/// - [Future] Synchronize with Firebase Firestore in background
///
/// Architecture:
/// - Uses GeofencesDAO for ObjectBox operations
/// - Stream controller for reactive UI updates
/// - In-memory cache for fast access
/// - Offline-first: all operations work locally first
class GeofenceRepository {
  GeofenceRepository({
    required GeofencesDaoBase dao,
  }) : _dao = dao {
    _init();
  }

  final GeofencesDaoBase _dao;

  // Stream controller for emitting geofences to UI
  final _geofencesController = StreamController<List<Geofence>>.broadcast();

  // Cached geofences list (in-memory)
  List<Geofence> _cachedGeofences = [];
  bool _initialized = false;
  bool _disposed = false;

  // Sync queue for offline changes (for future Firebase integration)
  final List<String> _syncQueue = [];
  Timer? _syncTimer;

  /// Stream of geofences for UI
  ///
  /// Emits initial cached data immediately to prevent loading states.
  Stream<List<Geofence>> watchGeofences(String userId) async* {
    _log('👀 watchGeofences() called for userId: $userId');

    // Emit current cache immediately
    if (_disposed) {
      _log('⏭️ Repository disposed, emitting empty list');
      yield const <Geofence>[];
    } else if (_cachedGeofences.isNotEmpty) {
      final userGeofences = _cachedGeofences
          .where((g) => g.userId == userId)
          .toList();
      _log('📤 Emitting initial cached geofences: ${userGeofences.length}');
      yield List.unmodifiable(userGeofences);
    } else {
      _log('📤 Emitting initial empty list');
      yield const <Geofence>[];
    }

    // Forward subsequent updates from broadcast controller
    yield* _geofencesController.stream.map((allGeofences) {
      return allGeofences.where((g) => g.userId == userId).toList();
    });
  }

  /// Initialize the repository
  void _init() {
    if (_initialized) return;
    _initialized = true;

    _log('🚀 Initializing GeofenceRepository');

    // Start async initialization
    _initAsync();
  }

  /// Async initialization
  Future<void> _initAsync() async {
    try {
      // Load cached geofences from ObjectBox
      await _loadCachedGeofences();

      // Start periodic sync timer (every 30 seconds) for future Firebase sync
      _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _processSyncQueue();
      });

      _log('✅ Repository initialized');
    } catch (e, stackTrace) {
      _log('❌ Failed to initialize repository: $e');
      if (kDebugMode) {
        debugPrint('[GeofenceRepository] Stack trace: $stackTrace');
      }
    }
  }

  /// Load cached geofences from ObjectBox
  Future<void> _loadCachedGeofences() async {
    try {
      _log('📦 Loading cached geofences from ObjectBox');
      _cachedGeofences = await _dao.getAllGeofences();

      // Sort by name
      _cachedGeofences.sort((a, b) => a.name.compareTo(b.name));

      _log('📦 Loaded ${_cachedGeofences.length} cached geofences');
      _emitGeofences();
    } catch (e) {
      _log('❌ Failed to load cached geofences: $e');
    }
  }

  /// Get a single geofence by ID
  Future<Geofence?> getGeofence(String id) async {
    try {
      _log('🔍 Getting geofence: $id');

      // Check cache first
      final cached = _cachedGeofences.where((g) => g.id == id).firstOrNull;
      if (cached != null) {
        return cached;
      }

      // Fallback to DAO
      return await _dao.getGeofence(id);
    } catch (e) {
      _log('❌ Failed to get geofence: $e');
      return null;
    }
  }

  /// Create a new geofence
  ///
  /// Offline-first: saves locally first.
  Future<void> createGeofence(Geofence geofence) async {
    try {
      _log('✏️ Creating geofence: ${geofence.name}');

      // Validate geofence
      if (!geofence.isValid()) {
        throw ArgumentError('Invalid geofence: validation failed');
      }

      // Mark as pending sync for future Firebase integration
      final pendingGeofence = geofence.copyWith(
        syncStatus: 'pending',
        version: 1,
      );

      // Save to ObjectBox
      await _dao.upsertGeofence(pendingGeofence);

      // Update cache
      _cachedGeofences.add(pendingGeofence);
      _cachedGeofences.sort((a, b) => a.name.compareTo(b.name));

      // Add to sync queue
      _syncQueue.add(pendingGeofence.id);

      _log('✅ Geofence created locally');
      _emitGeofences();

      // Trigger sync (will be no-op until Firebase is implemented)
      _processSyncQueue();
    } catch (e, stackTrace) {
      _log('❌ Failed to create geofence: $e');
      if (kDebugMode) {
        debugPrint('[GeofenceRepository] Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  /// Update an existing geofence
  ///
  /// Offline-first: updates locally first.
  Future<void> updateGeofence(Geofence geofence) async {
    try {
      _log('✏️ Updating geofence: ${geofence.name}');

      // Validate geofence
      if (!geofence.isValid()) {
        throw ArgumentError('Invalid geofence: validation failed');
      }

      // Increment version and mark as pending sync
      final updatedGeofence = geofence.copyWith(
        syncStatus: 'pending',
        version: geofence.version + 1,
        updatedAt: DateTime.now().toUtc(),
      );

      // Save to ObjectBox
      await _dao.upsertGeofence(updatedGeofence);

      // Update cache
      final index = _cachedGeofences.indexWhere((g) => g.id == geofence.id);
      if (index >= 0) {
        _cachedGeofences[index] = updatedGeofence;
      } else {
        _cachedGeofences.add(updatedGeofence);
      }
      _cachedGeofences.sort((a, b) => a.name.compareTo(b.name));

      // Add to sync queue
      if (!_syncQueue.contains(updatedGeofence.id)) {
        _syncQueue.add(updatedGeofence.id);
      }

      _log('✅ Geofence updated locally');
      _emitGeofences();

      // Trigger sync (will be no-op until Firebase is implemented)
      _processSyncQueue();
    } catch (e, stackTrace) {
      _log('❌ Failed to update geofence: $e');
      if (kDebugMode) {
        debugPrint('[GeofenceRepository] Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  /// Delete a geofence
  ///
  /// Deletes locally (cascade deletes events).
  Future<void> deleteGeofence(String id) async {
    try {
      _log('🗑️ Deleting geofence: $id');

      // Delete from ObjectBox (cascade deletes events)
      await _dao.deleteGeofence(id);

      // Update cache
      _cachedGeofences.removeWhere((g) => g.id == id);
      _syncQueue.remove(id);

      _log('✅ Geofence deleted locally');
      _emitGeofences();
    } catch (e, stackTrace) {
      _log('❌ Failed to delete geofence: $e');
      if (kDebugMode) {
        debugPrint('[GeofenceRepository] Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  /// Toggle geofence enabled status
  ///
  /// Quick operation for enabling/disabling geofences.
  Future<void> toggleGeofence(String id, bool enabled) async {
    try {
      _log('🔄 Toggling geofence $id to enabled=$enabled');

      final geofence = await getGeofence(id);
      if (geofence == null) {
        _log('⚠️ Geofence not found: $id');
        return;
      }

      // Update with new enabled status
      await updateGeofence(geofence.copyWith(enabled: enabled));

      _log('✅ Geofence toggled');
    } catch (e) {
      _log('❌ Failed to toggle geofence: $e');
      rethrow;
    }
  }

  /// Sync with Firestore for a specific user
  ///
  /// TODO: Implement when Firebase is added to the project.
  /// This is a placeholder for future cloud sync functionality.
  Future<void> syncWithFirestore(String userId) async {
    _log('📍 Firebase sync not yet implemented for userId: $userId');
    // This method is a placeholder for future Firebase integration.
    // When implemented, it will:
    // 1. Listen to Firestore collection for the user
    // 2. Merge remote changes with local cache
    // 3. Resolve conflicts using version + updatedAt fields
  }

  /// Process sync queue - upload pending geofences to cloud (future)
  Future<void> _processSyncQueue() async {
    if (_syncQueue.isEmpty) return;

    // TODO: Implement Firebase upload when package is added
    // For now, just mark as synced after a delay to simulate background sync
    _log('⬆️ Sync queue has ${_syncQueue.length} items (Firebase not yet integrated)');
    
    // Mark all as synced for now (local-only mode)
    for (final id in List<String>.from(_syncQueue)) {
      try {
        final geofence = await getGeofence(id);
        if (geofence != null && geofence.syncStatus == 'pending') {
          final syncedGeofence = geofence.copyWith(syncStatus: 'synced');
          await _dao.upsertGeofence(syncedGeofence);
          
          // Update cache
          final index = _cachedGeofences.indexWhere((g) => g.id == id);
          if (index >= 0) {
            _cachedGeofences[index] = syncedGeofence;
          }
        }
        _syncQueue.remove(id);
      } catch (e) {
        _log('⚠️ Failed to mark geofence synced: $id');
      }
    }
  }

  /// Emit current geofences to stream
  void _emitGeofences() {
    if (_disposed) {
      _log('⏭️ Skipping emit: repository disposed');
      return;
    }

    if (!_geofencesController.isClosed) {
      _log('📤 Emitting ${_cachedGeofences.length} geofences to stream');
      _geofencesController.add(List.unmodifiable(_cachedGeofences));
    }
  }

  /// Get current geofences snapshot (synchronous)
  List<Geofence> getCurrentGeofences() {
    return List.unmodifiable(_cachedGeofences);
  }

  /// Get enabled geofences for a user
  Future<List<Geofence>> getEnabledGeofences(String userId) async {
    try {
      final all = await _dao.getEnabledGeofences();
      return all.where((g) => g.userId == userId).toList();
    } catch (e) {
      _log('❌ Failed to get enabled geofences: $e');
      return [];
    }
  }

  /// Structured logging
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[GeofenceRepository] $message');
    }
  }

  /// Dispose resources
  void dispose() {
    if (_disposed) {
      _log('⚠️ Double dispose prevented');
      return;
    }
    _disposed = true;

    _log('🛑 Disposing GeofenceRepository');

    // Cancel subscriptions
    _syncTimer?.cancel();

    // Close stream controller
    _geofencesController.close();

    // Clear caches
    _cachedGeofences.clear();
    _syncQueue.clear();

    _log('✅ Repository disposed');
  }
}

/// Riverpod provider for GeofenceRepository
///
/// Returns a FutureProvider that resolves to the repository instance
/// once the DAO is ready. Uses keepAlive to maintain a single instance.
final geofenceRepositoryProvider = FutureProvider<GeofenceRepository>((ref) async {
  // Keep alive to maintain single repository instance
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(minutes: 10), link.close);
  });
  ref.onDispose(() => timer?.cancel());
  
  // Wait for DAO to be ready
  final dao = await ref.watch(geofencesDaoProvider.future);
  
  // Create repository
  final repository = GeofenceRepository(dao: dao);
  
  // Auto-dispose repository when provider is disposed
  ref.onDispose(repository.dispose);
  
  return repository;
});
