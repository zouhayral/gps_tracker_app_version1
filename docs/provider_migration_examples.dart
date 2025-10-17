// ignore_for_file: unused_import, undefined_class, undefined_method, non_type_as_type_argument, extends_non_class
// This file is documentation-only and intentionally contains placeholder
// classes and Flutter references. It is not intended to compile.

/*
// Example: How to Incrementally Adopt Granular Providers

// ============================================================================
// BEFORE: Traditional setState approach
// ============================================================================

class _OldMapPageState extends State<MapPage> {
  Set<int> _selectedIds = {};
  LatLng _center = LatLng(0, 0);
  double _zoom = 13;
  bool _showOnlineOnly = false;
  
  void selectDevice(int id) {
    setState(() {
      _selectedIds.add(id);
    });
    // ❌ This rebuilds the ENTIRE widget tree!
  }
  
  @override
  Widget build(BuildContext context) {
    // Every setState rebuilds everything
    return Column(
      children: [
        MapWidget(center: _center, zoom: _zoom), // Rebuilds unnecessarily
        DeviceList(selected: _selectedIds),      // Rebuilds unnecessarily
        FilterToggle(value: _showOnlineOnly),    // Rebuilds unnecessarily
      ],
    );
  }
}

// ============================================================================
// AFTER: Granular provider approach with .select()
// ============================================================================

class _NewMapPageState extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Each widget ONLY rebuilds when its specific data changes
        _MapWidget(),      // Only rebuilds when center/zoom changes
        _DeviceList(),     // Only rebuilds when selection changes
        _FilterToggle(),   // Only rebuilds when filter changes
      ],
    );
  }
}

class _MapWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ Only watches center and zoom - doesn't rebuild on selection/filter changes
    final center = ref.watch(mapCenterProvider);
    final zoom = ref.watch(mapZoomProvider);
    
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: zoom),
      // ...
    );
  }
}

class _DeviceList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
  // Example moved to docs/performance_validation_guide.md
  // This file intentionally left blank to avoid analyzer errors.
  final selectedId = ref.watch(selectedDeviceIdProvider);

*/
