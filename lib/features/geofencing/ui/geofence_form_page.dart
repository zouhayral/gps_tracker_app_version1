import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/core/navigation/safe_navigation.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';
import 'package:my_app_gps/features/geofencing/ui/widgets/geofence_map_widget.dart';
import 'package:my_app_gps/services/positions_service.dart';

/// Page mode for geofence form
enum GeofenceFormMode { create, edit }

/// Form page for creating and editing geofences.
///
/// This page allows users to:
/// - Create new circular or polygon geofences
/// - Edit existing geofences
/// - Configure triggers (entry, exit, dwell)
/// - Select monitored devices
/// - Configure notification settings
/// - Preview boundaries on an interactive map
///
/// ## Navigation
///
/// Create mode:
/// ```dart
/// context.push('/geofences/create');
/// ```
///
/// Edit mode:
/// ```dart
/// context.push('/geofences/${geofenceId}/edit');
/// ```
///
/// ## Example Route Configuration
/// ```dart
/// GoRoute(
///   path: '/geofences/create',
///   builder: (context, state) => const GeofenceFormPage(
///     mode: GeofenceFormMode.create,
///   ),
/// ),
/// GoRoute(
///   path: '/geofences/:id/edit',
///   builder: (context, state) {
///     final id = state.pathParameters['id']!;
///     return GeofenceFormPage(
///       mode: GeofenceFormMode.edit,
///       geofenceId: id,
///     );
///   },
/// ),
/// ```
///
/// ## Features
/// - Reactive form validation
/// - Interactive map drawing (placeholder)
/// - Material Design 3 styling
/// - Riverpod state management
/// - Error handling with feedback
class GeofenceFormPage extends ConsumerStatefulWidget {
  final GeofenceFormMode mode;
  final String? geofenceId;

  const GeofenceFormPage({
    required this.mode,
    this.geofenceId,
    super.key,
  });

  @override
  ConsumerState<GeofenceFormPage> createState() => _GeofenceFormPageState();
}

class _GeofenceFormPageState extends ConsumerState<GeofenceFormPage> {
  // Form key for validation
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Geofence type
  GeofenceType _type = GeofenceType.circle;

  // Circle properties
  LatLng? _circleCenter;
  double _circleRadius = 100.0; // meters

  // Polygon properties
  List<LatLng> _polygonVertices = [];

  // Triggers
  bool _onEnter = true;
  bool _onExit = true;
  bool _enableDwell = false;
  double _dwellMinutes = 5.0;

  // Devices
  Set<String> _selectedDevices = {};
  bool _allDevices = false;

  // Notifications
  String _notificationType = 'local';
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  String _priority = 'default';

  // State
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadGeofence();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Load existing geofence data in edit mode
  Future<void> _loadGeofence() async {
    if (widget.mode == GeofenceFormMode.edit && widget.geofenceId != null) {
      setState(() => _isLoading = true);

      try {
        final geofencesAsync = ref.read(geofencesProvider);
        await geofencesAsync.when(
          data: (geofences) async {
            final geofence = geofences.firstWhere(
              (g) => g.id == widget.geofenceId,
              orElse: () => throw Exception('Geofence not found'),
            );

            setState(() {
              _nameController.text = geofence.name;
              _type = geofence.type == 'circle'
                  ? GeofenceType.circle
                  : GeofenceType.polygon;

              if (geofence.type == 'circle') {
                _circleCenter = LatLng(
                  geofence.centerLat!,
                  geofence.centerLng!,
                );
                _circleRadius = geofence.radius ?? 100.0;
              } else {
                _polygonVertices = geofence.vertices ?? [];
              }

              _onEnter = geofence.onEnter;
              _onExit = geofence.onExit;
              _enableDwell = geofence.dwellMs != null && geofence.dwellMs! > 0;
              _dwellMinutes = geofence.dwellMs != null
                  ? geofence.dwellMs! / 60000.0
                  : 5.0;

              _selectedDevices = geofence.monitoredDevices.toSet();
              _allDevices = geofence.monitoredDevices.isEmpty;

              _notificationType = geofence.notificationType;
            });
          },
          loading: () async {},
          error: (e, s) async {
            if (mounted) {
              _showError('Error loading geofence: $e');
            }
          },
        );
      } catch (e) {
        if (mounted) {
          _showError('Error loading geofence: $e');
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.mode == GeofenceFormMode.create
              ? 'Create Geofence'
              : 'Edit Geofence',
        ),
        actions: [
          if (widget.mode == GeofenceFormMode.edit)
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Delete',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 80), // Space for FAB
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBasicInfoCard(theme),
                    _buildMapDrawingCard(theme),
                    _buildTriggersCard(theme),
                    _buildDevicesCard(theme),
                    _buildNotificationsCard(theme),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
      floatingActionButton: _isSaving
          ? const CircularProgressIndicator()
          : FloatingActionButton.extended(
              icon: const Icon(Icons.save),
              label: const Text('Save'),
              onPressed: _saveGeofence,
            ),
    );
  }

  /// Build basic info card
  Widget _buildBasicInfoCard(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.info, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Basic Information',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Name field
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                hintText: 'e.g., Home, Office, School',
                prefixIcon: Icon(Icons.label),
                border: OutlineInputBorder(),
              ),
              maxLength: 50,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                if (value.length > 50) {
                  return 'Name must be 50 characters or less';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Description field (optional)
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Add notes about this geofence',
                prefixIcon: Icon(Icons.description),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 200,
            ),

            const SizedBox(height: 16),

            // Type selector
            Text(
              'Type',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SegmentedButton<GeofenceType>(
              segments: const [
                ButtonSegment(
                  value: GeofenceType.circle,
                  label: Text('Circle'),
                  icon: Icon(Icons.circle_outlined),
                ),
                ButtonSegment(
                  value: GeofenceType.polygon,
                  label: Text('Polygon'),
                  icon: Icon(Icons.polyline),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (Set<GeofenceType> selection) {
                setState(() {
                  _type = selection.first;
                  // Reset map data when type changes
                  _circleCenter = null;
                  _circleRadius = 100.0;
                  _polygonVertices = [];
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build map drawing card
  Widget _buildMapDrawingCard(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.map, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Draw Boundary',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Interactive map widget
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 300,
                child: GeofenceMapWidget(
                  editable: true,
                  geofence: _buildPreviewGeofence(),
                  onShapeChanged: (shape) {
                    setState(() {
                      if (shape.type == 'circle') {
                        if (shape.center != null) {
                          _circleCenter = LatLng(
                            shape.center!.latitude,
                            shape.center!.longitude,
                          );
                        }
                        if (shape.radius != null) {
                          _circleRadius = shape.radius!;
                        }
                      } else {
                        _polygonVertices = shape.vertices
                                ?.map((v) => LatLng(v.latitude, v.longitude))
                                .toList() ??
                            [];
                      }
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Circle radius slider
            if (_type == GeofenceType.circle) ...[
              Text(
                'Radius: ${_formatDistance(_circleRadius)}',
                style: theme.textTheme.labelLarge,
              ),
              Slider(
                value: _circleRadius,
                min: 10,
                max: 10000,
                divisions: 100,
                label: _formatDistance(_circleRadius),
                onChanged: (value) {
                  setState(() {
                    _circleRadius = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('10 m', style: theme.textTheme.bodySmall),
                  Text('10 km', style: theme.textTheme.bodySmall),
                ],
              ),
            ],

            // Polygon info
            if (_type == GeofenceType.polygon) ...[
              Row(
                children: [
                  Icon(
                    Icons.polyline,
                    size: 16,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Vertices: ${_polygonVertices.length}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const Spacer(),
                  if (_polygonVertices.length >= 3)
                    Text(
                      'Area: ${_calculatePolygonArea()}',
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
              if (_polygonVertices.length < 3)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'At least 3 vertices required',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 16),

            // Quick location button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.my_location),
                label: const Text('Use Current Location'),
                onPressed: _useCurrentLocation,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build triggers card
  Widget _buildTriggersCard(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.notifications_active, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Triggers',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // On Enter toggle
            SwitchListTile(
              title: const Text('On Enter'),
              subtitle: const Text('Trigger when device enters this area'),
              value: _onEnter,
              onChanged: (value) {
                setState(() {
                  _onEnter = value;
                });
              },
              secondary: const Icon(Icons.login),
            ),

            // On Exit toggle
            SwitchListTile(
              title: const Text('On Exit'),
              subtitle: const Text('Trigger when device leaves this area'),
              value: _onExit,
              onChanged: (value) {
                setState(() {
                  _onExit = value;
                });
              },
              secondary: const Icon(Icons.logout),
            ),

            // Dwell toggle
            SwitchListTile(
              title: const Text('Dwell Time'),
              subtitle: Text(
                _enableDwell
                    ? 'Trigger after ${_dwellMinutes.toInt()} minutes'
                    : 'Trigger when device stays in area',
              ),
              value: _enableDwell,
              onChanged: (value) {
                setState(() {
                  _enableDwell = value;
                });
              },
              secondary: const Icon(Icons.schedule),
            ),

            // Dwell duration slider
            if (_enableDwell) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dwell Duration: ${_dwellMinutes.toInt()} minutes',
                      style: theme.textTheme.labelLarge,
                    ),
                    Slider(
                      value: _dwellMinutes,
                      min: 1,
                      max: 60,
                      divisions: 59,
                      label: '${_dwellMinutes.toInt()} min',
                      onChanged: (value) {
                        setState(() {
                          _dwellMinutes = value;
                        });
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('1 min', style: theme.textTheme.bodySmall),
                        Text('60 min', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Validation message
            if (!_onEnter && !_onExit && !_enableDwell)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'At least one trigger must be enabled',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build devices card
  Widget _buildDevicesCard(ThemeData theme) {
    // Fetch actual devices from Traccar API
    final devicesAsync = ref.watch(devicesNotifierProvider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.devices, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Monitored Devices',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // All devices toggle
            SwitchListTile(
              title: const Text('All Devices'),
              subtitle: const Text('Monitor all devices automatically'),
              value: _allDevices,
              onChanged: (value) {
                setState(() {
                  _allDevices = value;
                  if (value) {
                    _selectedDevices.clear();
                  }
                });
              },
              secondary: const Icon(Icons.select_all),
            ),

            const Divider(),

            // Device list - handle loading/error states
            Builder(
              builder: (context) {
                return devicesAsync.when(
                  data: (List<Map<String, dynamic>> devices) {
                    if (devices.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            'No devices available',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      );
                    }

                    // Device list
                    if (!_allDevices) {
                      return Column(
                        children: [
                          ...devices.map((Map<String, dynamic> device) {
                            final deviceId = device['id']?.toString() ?? '';
                            final deviceName = device['name']?.toString() ?? 'Device $deviceId';
                            final isSelected = _selectedDevices.contains(deviceId);
                            
                            return CheckboxListTile(
                              title: Text(deviceName),
                              value: isSelected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedDevices.add(deviceId);
                                  } else {
                                    _selectedDevices.remove(deviceId);
                                  }
                                });
                              },
                              secondary: const Icon(Icons.smartphone),
                            );
                          }),
                          if (_selectedDevices.isEmpty && !_allDevices)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Select at least one device or enable "All Devices"',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      );
                    } else {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'All current and future devices will be monitored',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (Object error, StackTrace stack) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Error loading devices: $error',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build notifications card
  Widget _buildNotificationsCard(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.notifications, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Notifications',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Notification type
            Text(
              'Type',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'local',
                  label: Text('Local'),
                  icon: Icon(Icons.notifications),
                ),
                ButtonSegment(
                  value: 'push',
                  label: Text('Push'),
                  icon: Icon(Icons.cloud),
                ),
                ButtonSegment(
                  value: 'both',
                  label: Text('Both'),
                  icon: Icon(Icons.notifications_active),
                ),
              ],
              selected: {_notificationType},
              onSelectionChanged: (Set<String> selection) {
                setState(() {
                  _notificationType = selection.first;
                });
              },
            ),

            const SizedBox(height: 16),

            // Sound toggle
            SwitchListTile(
              title: const Text('Sound'),
              subtitle: const Text('Play notification sound'),
              value: _soundEnabled,
              onChanged: (value) {
                setState(() {
                  _soundEnabled = value;
                });
              },
              secondary: const Icon(Icons.volume_up),
            ),

            // Vibration toggle
            SwitchListTile(
              title: const Text('Vibration'),
              subtitle: const Text('Vibrate on notification'),
              value: _vibrationEnabled,
              onChanged: (value) {
                setState(() {
                  _vibrationEnabled = value;
                });
              },
              secondary: const Icon(Icons.vibration),
            ),

            const SizedBox(height: 16),

            // Priority dropdown
            DropdownMenu<String>(
              label: const Text('Priority'),
              leadingIcon: const Icon(Icons.priority_high),
              initialSelection: _priority,
              onSelected: (value) {
                if (value != null) {
                  setState(() {
                    _priority = value;
                  });
                }
              },
              dropdownMenuEntries: const [
                DropdownMenuEntry(value: 'low', label: 'Low'),
                DropdownMenuEntry(value: 'default', label: 'Default'),
                DropdownMenuEntry(value: 'high', label: 'High'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Validate form data
  bool _validateForm() {
    // Validate form fields
    if (!_formKey.currentState!.validate()) {
      return false;
    }

    // Validate map data
    if (_type == GeofenceType.circle) {
      if (_circleCenter == null) {
        _showError('Please set the geofence center on the map');
        return false;
      }
      if (_circleRadius < 10 || _circleRadius > 10000) {
        _showError('Radius must be between 10m and 10km');
        return false;
      }
    } else {
      if (_polygonVertices.length < 3) {
        _showError('Polygon must have at least 3 vertices');
        return false;
      }
    }

    // Validate triggers
    if (!_onEnter && !_onExit && !_enableDwell) {
      _showError('At least one trigger must be enabled');
      return false;
    }

    // Validate devices
    if (!_allDevices && _selectedDevices.isEmpty) {
      _showError('Select at least one device or enable "All Devices"');
      return false;
    }

    return true;
  }

  /// Save geofence
  Future<void> _saveGeofence() async {
    if (!_validateForm()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Wait for repository to be ready
      final repo = await ref.read(geofenceRepositoryProvider.future);
      final now = DateTime.now();

      final geofence = Geofence(
        id: widget.geofenceId ?? 'geofence_${now.millisecondsSinceEpoch}',
        userId: 'test-user-id', // TODO: Get from auth provider (must match geofencesProvider)
        name: _nameController.text.trim(),
        type: _type == GeofenceType.circle ? 'circle' : 'polygon',
        enabled: true,
        centerLat: _type == GeofenceType.circle ? _circleCenter?.latitude : null,
        centerLng: _type == GeofenceType.circle ? _circleCenter?.longitude : null,
        radius: _type == GeofenceType.circle ? _circleRadius : null,
        vertices: _type == GeofenceType.polygon ? _polygonVertices : null,
        monitoredDevices: _allDevices ? [] : _selectedDevices.toList(),
        onEnter: _onEnter,
        onExit: _onExit,
        dwellMs: _enableDwell ? (_dwellMinutes * 60000).toInt() : null,
        notificationType: _notificationType,
        createdAt: widget.mode == GeofenceFormMode.create ? now : DateTime.now(),
        updatedAt: now,
        syncStatus: 'pending',
        version: 1,
      );

      if (widget.mode == GeofenceFormMode.create) {
        await repo.createGeofence(geofence);
      } else {
        await repo.updateGeofence(geofence);
      }

      if (mounted) {
        // Invalidate providers to trigger UI refresh
        ref.invalidate(geofencesProvider);
        ref.invalidate(geofenceStatsProvider);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.mode == GeofenceFormMode.create
                  ? 'Geofence created successfully'
                  : 'Geofence updated successfully',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );

        // Navigate back - check if context is still mounted
        if (!context.mounted) {
          debugPrint('[SafeNav] Skipped navigation: context not mounted after save');
          return;
        }
        context.safePop<void>();
      }
    } catch (e) {
      if (mounted) {
        _showError('Error saving geofence: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Confirm and delete geofence
  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Geofence'),
        content: const Text(
          'Are you sure you want to delete this geofence?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.safePop<bool>(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.safePop<bool>(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        // Wait for repository to be ready
        final repo = await ref.read(geofenceRepositoryProvider.future);
        await repo.deleteGeofence(widget.geofenceId!);

        if (mounted) {
          // Invalidate providers to trigger UI refresh
          ref.invalidate(geofencesProvider);
          ref.invalidate(geofenceStatsProvider);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Geofence deleted successfully'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );

          // Check if context is still mounted after async operations
          if (!context.mounted) {
            debugPrint('[SafeNav] Skipped navigation: context not mounted after delete');
            return;
          }
          context.safePop<void>();
        }
      } catch (e) {
        if (mounted) {
          _showError('Error deleting geofence: $e');
        }
      }
    }
  }

  /// Build a preview geofence object for the map widget
  Geofence _buildPreviewGeofence() {
    return Geofence(
      id: widget.geofenceId ?? '',
      userId: '', // Will be set on save
      name: _nameController.text.isNotEmpty ? _nameController.text : 'New Geofence',
      type: _type == GeofenceType.circle ? 'circle' : 'polygon',
      centerLat: _circleCenter?.latitude,
      centerLng: _circleCenter?.longitude,
      radius: _type == GeofenceType.circle ? _circleRadius : null,
      vertices: _type == GeofenceType.polygon ? _polygonVertices : null,
      enabled: true,
      monitoredDevices: _selectedDevices.toList(),
      onEnter: _onEnter,
      onExit: _onExit,
      dwellMs: _enableDwell ? (_dwellMinutes * 60 * 1000).round() : null,
      notificationType: _notificationType,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Use current location - shows dialog with options
  Future<void> _useCurrentLocation() async {
    // Show dialog with options
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Phone Current Location'),
              subtitle: const Text('Use GPS from this device'),
              onTap: () => context.safePop<String>('phone'),
            ),
            ListTile(
              leading: const Icon(Icons.directions_car),
              title: const Text('Vehicle Location'),
              subtitle: const Text('Use tracked vehicle position'),
              onTap: () => context.safePop<String>('vehicle'),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'phone') {
      await _usePhoneLocation();
    } else if (choice == 'vehicle') {
      await _showVehicleLocationDialog();
    }
  }

  /// Get phone's current GPS location
  Future<void> _usePhoneLocation() async {
    try {
      // Check location service
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showError('Location services are disabled. Please enable GPS.');
        }
        return;
      }

      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            _showError('Location permission denied');
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showError('Location permission permanently denied. Please enable in settings.');
        }
        return;
      }

      // Get current position
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Getting your location...'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      if (mounted) {
        setState(() {
          _circleCenter = LatLng(position.latitude, position.longitude);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Location set: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to get location: $e');
      }
    }
  }

  /// Show dialog to select vehicle location
  Future<void> _showVehicleLocationDialog() async {
    final devicesAsync = ref.read(devicesNotifierProvider);
    
    await devicesAsync.when(
      data: (devices) async {
        if (devices.isEmpty) {
          if (mounted) {
            _showError('No vehicles found');
          }
          return;
        }

        // Fetch positions for all devices
        final positionsService = ref.read(positionsServiceProvider);
        final List<Map<String, dynamic>> deviceLocations = [];

        for (final device in devices) {
          try {
            final deviceId = device['id'] as int;
            final positions = await positionsService.fetchHistoryRaw(
              deviceId: deviceId,
              from: DateTime.now().subtract(const Duration(hours: 1)),
              to: DateTime.now(),
            );

            if (positions.isNotEmpty) {
              final lastPosition = positions.last as Map<String, dynamic>;
              deviceLocations.add({
                'id': deviceId,
                'name': device['name'] ?? 'Device $deviceId',
                'latitude': lastPosition['latitude'] as double,
                'longitude': lastPosition['longitude'] as double,
                'timestamp': DateTime.parse(lastPosition['fixTime'] as String),
              });
            }
          } catch (e) {
            // Skip this device if error
            continue;
          }
        }

        if (!mounted) return;

        if (deviceLocations.isEmpty) {
          _showError('No recent vehicle locations found');
          return;
        }

        // Show dialog with vehicle locations
        final selectedLocation = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Select Vehicle Location'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: deviceLocations.length,
                itemBuilder: (context, index) {
                  final location = deviceLocations[index];
                  final timestamp = location['timestamp'] as DateTime;
                  final timeAgo = DateTime.now().difference(timestamp);
                  final timeText = timeAgo.inHours > 0
                      ? '${timeAgo.inHours}h ago'
                      : '${timeAgo.inMinutes}m ago';

                  return ListTile(
                    leading: const Icon(Icons.location_on, color: Colors.blue),
                    title: Text(location['name'] as String),
                    subtitle: Text(
                      '${(location['latitude'] as double).toStringAsFixed(5)}, '
                      '${(location['longitude'] as double).toStringAsFixed(5)}\n'
                      'Updated: $timeText',
                    ),
                    isThreeLine: true,
                    onTap: () => context.safePop<Map<String, dynamic>>(location),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => context.safePop<Map<String, dynamic>?>(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );

        if (selectedLocation != null && mounted) {
          setState(() {
            _circleCenter = LatLng(
              selectedLocation['latitude'] as double,
              selectedLocation['longitude'] as double,
            );
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Location set to ${selectedLocation['name']}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      loading: () {
        if (mounted) {
          _showError('Loading vehicles...');
        }
      },
      error: (error, _) {
        if (mounted) {
          _showError('Error loading vehicles: $error');
        }
      },
    );
  }

  /// Calculate polygon area
  String _calculatePolygonArea() {
    if (_polygonVertices.length < 3) {
      return '0 m²';
    }

    // TODO: Calculate actual area using geodesic calculations
    // For now, return placeholder
    return '~1000 m²';
  }

  /// Format distance
  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  /// Show error message
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// =============================================================================
// ENUMS
// =============================================================================

/// Geofence type enum
enum GeofenceType { circle, polygon }

// =============================================================================
// ROUTE REGISTRATION EXAMPLE
// =============================================================================

/*
/// Example GoRouter configuration
final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomePage(),
      routes: [
        GoRoute(
          path: 'geofences',
          builder: (context, state) => const GeofenceListPage(),
          routes: [
            // Create geofence
            GoRoute(
              path: 'create',
              builder: (context, state) => const GeofenceFormPage(
                mode: GeofenceFormMode.create,
              ),
            ),
            // Geofence details
            GoRoute(
              path: ':id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return GeofenceDetailPage(geofenceId: id);
              },
              routes: [
                // Edit geofence
                GoRoute(
                  path: 'edit',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return GeofenceFormPage(
                      mode: GeofenceFormMode.edit,
                      geofenceId: id,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
*/

// =============================================================================
// USAGE EXAMPLES
// =============================================================================

/*
/// Example: Navigate to create page
void navigateToCreate(BuildContext context) {
  context.safePush<void>('/geofences/create');
}

/// Example: Navigate to edit page
void navigateToEdit(BuildContext context, String geofenceId) {
  context.safePush<void>('/geofences/$geofenceId/edit');
}

/// Example: Custom validation
bool _customValidation() {
  // Add custom validation logic
  if (_circleRadius < 50) {
    _showError('Radius too small for reliable detection');
    return false;
  }
  return true;
}

/// Example: Pre-fill form with template
void _loadTemplate(GeofenceTemplate template) {
  setState(() {
    _nameController.text = template.name;
    _type = template.type;
    _circleRadius = template.defaultRadius;
    _onEnter = template.defaultTriggers.contains('enter');
    _onExit = template.defaultTriggers.contains('exit');
  });
}
*/
