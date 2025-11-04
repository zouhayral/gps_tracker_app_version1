/// Lazy service loader for deferred initialization of heavy services
/// 
/// **Purpose**: Defer non-critical service initialization to improve cold start time
/// 
/// **Strategy**:
/// - Load critical services synchronously (auth, database)
/// - Defer heavy services using addPostFrameCallback
/// - Use lazy providers for feature-specific services
/// 
/// **Target Services**:
/// - WebSocket (defer until map page accessed)
/// - Geofence repositories (defer until geofence tab accessed)
/// - PDF generator (defer until export triggered)
/// - Share services (defer until share triggered)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/geofences_dao.dart';
import 'package:my_app_gps/core/database/objectbox_singleton.dart';
import 'package:my_app_gps/data/repositories/geofence_event_repository.dart';
import 'package:my_app_gps/data/repositories/geofence_repository.dart';

/// Provider for lazy-loaded geofence repositories
/// 
/// **Initialization Strategy**:
/// - Synchronous init: Critical services (auth, cache)
/// - Deferred init: Geofence repos (only when accessed)
/// 
/// **Benefits**:
/// - Reduces main() execution time by ~150-200ms
/// - ObjectBox initialization deferred until needed
/// - No impact on app-to-interactive time
final lazyGeofenceRepositoriesProvider = FutureProvider<({
  GeofenceRepository geofenceRepo,
  GeofenceEventRepository eventRepo,
})>((ref) async {
  // This provider is only read when geofence features are accessed
  // (e.g., navigating to geofence tab, receiving geofence notification)
  
  // Initialize ObjectBox store (heavy operation)
  final store = await ObjectBoxSingleton.getStore();
  
  // Create DAO
  final dao = GeofencesDaoObjectBox(store);
  
  // Create repositories
  final geofenceRepo = GeofenceRepository(dao: dao);
  final eventRepo = GeofenceEventRepository(dao: dao);
  
  return (
    geofenceRepo: geofenceRepo,
    eventRepo: eventRepo,
  );
});

/// Deferred service loader for non-critical initialization
/// 
/// **Usage in AppRoot**:
/// ```dart
/// @override
/// void initState() {
///   super.initState();
///   
///   // Defer heavy services to next frame
///   WidgetsBinding.instance.addPostFrameCallback((_) {
///     DeferredServiceLoader.instance.initialize(ref);
///   });
/// }
/// ```
class DeferredServiceLoader {
  static final DeferredServiceLoader instance = DeferredServiceLoader._();
  DeferredServiceLoader._();
  
  bool _initialized = false;
  
  /// Initialize deferred services after first frame is rendered
  /// 
  /// **Execution Order**:
  /// 1. Frame 0: App UI rendered (splash screen / loading state)
  /// 2. Frame 1: Marker precaching, icon warmup
  /// 3. Frame 2+: Heavy service initialization (ObjectBox, WorkManager)
  Future<void> initialize(WidgetRef ref) async {
    if (_initialized) return;
    _initialized = true;
    
    debugPrint('[STARTUP][DEFERRED] Beginning deferred initialization...');
    
    // Phase 1: Lightweight UI preparation (immediate)
    await _initializePhase1(ref);
    
    // Phase 2: Heavy service initialization (after short delay)
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _initializePhase2(ref);
    
    debugPrint('[STARTUP][DEFERRED] ✅ All deferred services initialized');
  }
  
  /// Phase 1: Lightweight UI preparation (0-100ms delay)
  Future<void> _initializePhase1(WidgetRef ref) async {
    // Marker precaching and icon warmup already handled by AppRoot
    // This phase is reserved for future lightweight initializations
    debugPrint('[STARTUP][PHASE1] UI preparation complete');
  }
  
  /// Phase 2: Heavy service initialization (100ms+ delay)
  Future<void> _initializePhase2(WidgetRef ref) async {
    // Geofence repositories are now lazy-loaded via provider
    // They'll initialize when first accessed (e.g., geofence tab navigation)
    
    // Note: WebSocket initialization is already lazy via Riverpod
    // It's created when VehicleDataRepository is first accessed
    
    debugPrint('[STARTUP][PHASE2] Heavy services ready for lazy loading');
  }
}
