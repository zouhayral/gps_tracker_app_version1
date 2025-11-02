import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:my_app_gps/core/navigation/safe_navigation.dart';

/// Education dialog shown when background location permission is denied.
///
/// Provides clear explanation and guidance to help users enable
/// background location access in system settings.
///
/// Platform-specific messaging:
/// - **Android**: "Allow all the time" permission required
/// - **iOS**: "Always Allow" permission required
class PermissionPromptDialog extends StatelessWidget {
  /// Callback to open system app settings
  final VoidCallback onOpenSettings;

  /// Optional custom title
  final String? title;

  /// Optional custom message
  final String? message;

  const PermissionPromptDialog({
    required this.onOpenSettings, super.key,
    this.title,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      icon: Icon(
        Icons.location_off_rounded,
        size: 48,
        color: colorScheme.error,
      ),
      title: Text(
        title ?? 'Enable Background Location',
        style: theme.textTheme.headlineSmall,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message ?? _getDefaultMessage(),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _buildInstructionsList(theme),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This ensures geofence alerts work even when the app is closed.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.safePop<void>(),
          child: const Text('Maybe Later'),
        ),
        FilledButton.icon(
          onPressed: () {
            context.safePop<void>();
            onOpenSettings();
          },
          icon: const Icon(Icons.settings_rounded),
          label: const Text('Open Settings'),
        ),
      ],
    );
  }

  String _getDefaultMessage() {
    if (Platform.isAndroid) {
      return 'To receive geofence alerts while the app is closed or in the background, '
          'please enable "Allow all the time" location permission.';
    } else if (Platform.isIOS) {
      return 'To receive geofence alerts while the app is closed or in the background, '
          'please enable "Always Allow" location access.';
    }
    return 'Background location access is required for geofence monitoring.';
  }

  Widget _buildInstructionsList(ThemeData theme) {
    final steps = _getSteps();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Steps:',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  List<String> _getSteps() {
    if (Platform.isAndroid) {
      return [
        'Tap "Open Settings" below',
        'Find "Location" or "Permissions"',
        'Select "Allow all the time"',
        'Return to the app',
      ];
    } else if (Platform.isIOS) {
      return [
        'Tap "Open Settings" below',
        'Find "Location" in the list',
        'Select "Always"',
        'Return to the app',
      ];
    }
    return [
      'Tap "Open Settings" below',
      'Enable background location access',
      'Return to the app',
    ];
  }
}

/// Compact version of permission prompt for inline use (e.g., in banners)
class PermissionPromptBanner extends StatelessWidget {
  final VoidCallback onOpenSettings;
  final VoidCallback? onDismiss;

  const PermissionPromptBanner({
    required this.onOpenSettings, super.key,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.error.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.location_off_rounded,
                color: colorScheme.onErrorContainer,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Background Location Needed',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 20,
                  onPressed: onDismiss,
                  color: colorScheme.onErrorContainer,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            Platform.isAndroid
                ? 'Enable "Allow all the time" for background geofence alerts.'
                : 'Enable "Always Allow" for background geofence alerts.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_rounded),
            label: const Text('Open Settings'),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
          ),
        ],
      ),
    );
  }
}

/// Foreground-only mode banner (shown when background denied)
class ForegroundOnlyBanner extends StatelessWidget {
  final VoidCallback? onLearnMore;

  const ForegroundOnlyBanner({
    super.key,
    this.onLearnMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.secondary.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: colorScheme.onSecondaryContainer,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Foreground-Only Mode',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Geofence monitoring works only while app is open.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          if (onLearnMore != null)
            TextButton(
              onPressed: onLearnMore,
              child: const Text('Learn More'),
            ),
        ],
      ),
    );
  }
}
