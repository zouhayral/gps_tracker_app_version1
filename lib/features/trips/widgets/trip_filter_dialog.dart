import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_app_gps/features/trips/models/trip_filter.dart';

/// Dialog for selecting trip filter options (devices and date range)
class TripFilterDialog extends StatefulWidget {
  const TripFilterDialog({
    required this.devices,
    this.initialFilter,
    super.key,
  });

  final List<Map<String, dynamic>> devices;
  final TripFilter? initialFilter;

  @override
  State<TripFilterDialog> createState() => _TripFilterDialogState();
}

class _TripFilterDialogState extends State<TripFilterDialog> {
  late Set<int> _selectedDeviceIds;
  late DateTimeRange _dateRange;

  @override
  void initState() {
    super.initState();
    
    // Initialize from existing filter or defaults
    if (widget.initialFilter != null) {
      _selectedDeviceIds = widget.initialFilter!.deviceIds.toSet();
      _dateRange = DateTimeRange(
        start: widget.initialFilter!.from,
        end: widget.initialFilter!.to,
      );
    } else {
      _selectedDeviceIds = {};
      final now = DateTime.now();
      _dateRange = DateTimeRange(
        start: now.subtract(const Duration(days: 1)),
        end: now,
      );
    }
  }

  bool get _isAllDevicesSelected => _selectedDeviceIds.isEmpty;

  void _toggleAllDevices() {
    setState(() {
      if (_isAllDevicesSelected) {
        // Select first device as example
        if (widget.devices.isNotEmpty) {
          final firstDeviceId = widget.devices.first['id'] as int?;
          if (firstDeviceId != null) {
            _selectedDeviceIds = {firstDeviceId};
          }
        }
      } else {
        // Clear selection (= all devices)
        _selectedDeviceIds.clear();
      }
    });
  }

  void _toggleDevice(int deviceId) {
    setState(() {
      if (_selectedDeviceIds.contains(deviceId)) {
        _selectedDeviceIds.remove(deviceId);
      } else {
        _selectedDeviceIds.add(deviceId);
      }
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _dateRange,
    );
    
    if (picked != null) {
      setState(() {
        _dateRange = DateTimeRange(
          start: DateTime(picked.start.year, picked.start.month, picked.start.day),
          end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
        );
      });
    }
  }

  void _applyFilter() {
    final filter = TripFilter(
      deviceIds: _selectedDeviceIds.toList(),
      from: _dateRange.start,
      to: _dateRange.end,
    );
    Navigator.of(context).pop(filter);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Filter Trips',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Date Range Section
                    Text(
                      'Date Range',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickDateRange,
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        _formatDateRange(_dateRange),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Device Selection Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Devices',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (_selectedDeviceIds.isNotEmpty)
                          Text(
                            '${_selectedDeviceIds.length} selected',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // "All Devices" option
                    CheckboxListTile(
                      value: _isAllDevicesSelected,
                      onChanged: (_) => _toggleAllDevices(),
                      title: Row(
                        children: [
                          Icon(
                            Icons.devices,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'All Devices',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '${widget.devices.length} devices available',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
              color: _isAllDevicesSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
            tileColor: _isAllDevicesSelected
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
                    ),
                    const SizedBox(height: 12),

                    // Divider with "OR"
                    if (!_isAllDevicesSelected) ...[
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'OR SELECT SPECIFIC',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Individual device checkboxes
                    if (!_isAllDevicesSelected)
                      ...widget.devices.map((device) {
                        final deviceId = device['id'] as int?;
                        final deviceName = device['name'] as String? ?? 'Unknown';
                        if (deviceId == null) return const SizedBox.shrink();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: CheckboxListTile(
                            value: _selectedDeviceIds.contains(deviceId),
                            onChanged: (_) => _toggleDevice(deviceId),
                            title: Text(
                              deviceName,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            secondary: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.directions_car,
                                size: 20,
                                color: Theme.of(context).colorScheme.onSecondaryContainer,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                color: _selectedDeviceIds.contains(deviceId)
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                              ),
                            ),
              tileColor: _selectedDeviceIds.contains(deviceId)
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _applyFilter,
                    icon: const Icon(Icons.check),
                    label: const Text('Apply Filter'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateRange(DateTimeRange range) {
    final formatter = DateFormat('MMM d, yyyy');
    return '${formatter.format(range.start)} - ${formatter.format(range.end)}';
  }
}
