import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_form_state.dart';
import 'package:my_app_gps/features/geofencing/ui/geofence_form_page.dart';

/// Extracted widgets for geofence form
/// These widgets demonstrate the refactoring pattern to eliminate setState calls

/// Reusable toggle widget for triggers
class TriggerToggle extends StatelessWidget {
  const TriggerToggle({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
    super.key,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(label),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      secondary: icon != null ? Icon(icon) : null,
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Circle radius slider with provider integration
class CircleRadiusSlider extends ConsumerWidget {
  const CircleRadiusSlider({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Selective watching - only rebuilds when radius changes
    final radius = ref.watch(
      geofenceFormProvider.select((state) => state.circleRadius),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Radius',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${radius.toStringAsFixed(0)} m',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: radius,
          min: 50,
          max: 5000,
          divisions: 99,
          label: '${radius.toStringAsFixed(0)} m',
          onChanged: (value) {
            ref.read(geofenceFormProvider.notifier).setCircleRadius(value);
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '50 m',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '5000 m',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

/// Dwell time slider with provider integration
class DwellTimeSlider extends ConsumerWidget {
  const DwellTimeSlider({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Selective watching - only rebuilds when dwell time changes
    final dwellMinutes = ref.watch(
      geofenceFormProvider.select((state) => state.dwellMinutes),
    );
    final enableDwell = ref.watch(
      geofenceFormProvider.select((state) => state.enableDwell),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Dwell Time',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${dwellMinutes.toStringAsFixed(0)} min',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: enableDwell
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: dwellMinutes,
          min: 1,
          max: 60,
          divisions: 59,
          label: '${dwellMinutes.toStringAsFixed(0)} min',
          onChanged: enableDwell
              ? (value) {
                  ref.read(geofenceFormProvider.notifier).setDwellMinutes(value);
                }
              : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '1 min',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '60 min',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

/// Geofence type selector with provider integration
class GeofenceTypeSelector extends ConsumerWidget {
  const GeofenceTypeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(
      geofenceFormProvider.select((state) => state.type),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Geofence Type',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<GeofenceType>(
          segments: const [
            ButtonSegment<GeofenceType>(
              value: GeofenceType.circle,
              label: Text('Circle'),
              icon: Icon(Icons.circle_outlined),
            ),
            ButtonSegment<GeofenceType>(
              value: GeofenceType.polygon,
              label: Text('Polygon'),
              icon: Icon(Icons.pentagon_outlined),
            ),
          ],
          selected: {type},
          onSelectionChanged: (Set<GeofenceType> newSelection) {
            ref.read(geofenceFormProvider.notifier).setType(newSelection.first);
          },
        ),
      ],
    );
  }
}

/// Notification type selector with provider integration
class NotificationTypeSelector extends ConsumerWidget {
  const NotificationTypeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationType = ref.watch(
      geofenceFormProvider.select((state) => state.notificationType),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notification Type',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: notificationType,
          decoration: const InputDecoration(
            labelText: 'Type',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: 'local',
              child: Text('Local Notification'),
            ),
            DropdownMenuItem(
              value: 'push',
              child: Text('Push Notification'),
            ),
            DropdownMenuItem(
              value: 'both',
              child: Text('Both'),
            ),
            DropdownMenuItem(
              value: 'none',
              child: Text('None'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              ref.read(geofenceFormProvider.notifier).setNotificationType(value);
            }
          },
        ),
      ],
    );
  }
}

/// Device checkbox item
class DeviceCheckbox extends ConsumerWidget {
  const DeviceCheckbox({
    required this.deviceId,
    required this.deviceName,
    super.key,
  });

  final String deviceId;
  final String deviceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDevices = ref.watch(
      geofenceFormProvider.select((state) => state.selectedDevices),
    );
    final allDevices = ref.watch(
      geofenceFormProvider.select((state) => state.allDevices),
    );

    final isSelected = selectedDevices.contains(deviceId);

    return CheckboxListTile(
      title: Text(deviceName),
      value: isSelected,
      enabled: !allDevices,
      onChanged: allDevices
          ? null
          : (value) {
              ref.read(geofenceFormProvider.notifier).toggleDevice(deviceId);
            },
    );
  }
}

/// Notification toggle (reusable)
class NotificationToggle extends StatelessWidget {
  const NotificationToggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(label),
      secondary: icon != null ? Icon(icon) : null,
      value: value,
      onChanged: onChanged,
    );
  }
}
