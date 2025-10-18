/// Prefetch settings panel widget
///
/// Provides UI controls for:
/// - Enable/disable prefetch
/// - Profile selection (Light, Commute, Heavy)
/// - Manual "Prefetch Current View" trigger
/// - Progress display during active prefetch
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:my_app_gps/prefetch/prefetch_profile.dart';
import 'package:my_app_gps/prefetch/prefetch_progress.dart';
import 'package:my_app_gps/providers/prefetch_provider.dart';
import 'package:my_app_gps/map/map_tile_source_provider.dart';

/// Prefetch settings and control panel
class PrefetchPanel extends ConsumerWidget {
  /// Current map center (for manual prefetch trigger)
  final LatLng? currentCenter;

  const PrefetchPanel({
    super.key,
    this.currentCenter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(prefetchSettingsProvider);
    final progress = ref.watch(currentPrefetchProgressProvider);
    final tileSource = ref.watch(mapTileSourceProvider);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.download, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Offline Prefetch',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const Divider(height: 24),

            // Enable toggle
            SwitchListTile(
              title: const Text('Enable Prefetch'),
              subtitle: const Text('Download tiles for offline use'),
              value: settings.enabled,
              onChanged: (enabled) {
                ref.read(prefetchSettingsProvider.notifier).setEnabled(enabled);
              },
            ),

            if (settings.enabled) ...[
              const SizedBox(height: 16),

              // Profile selector
              DropdownButtonFormField<PrefetchProfile>(
                decoration: const InputDecoration(
                  labelText: 'Profile',
                  border: OutlineInputBorder(),
                ),
                value: settings.selectedProfile,
                items: PrefetchProfile.builtInProfiles.map((profile) {
                  return DropdownMenuItem(
                    value: profile,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(profile.name),
                        Text(
                          '${profile.zoomMin}-${profile.zoomMax} zoom, '
                          '${profile.radiusKm}km radius, '
                          '~${profile.estimateTileCount()} tiles',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (profile) {
                  if (profile != null) {
                    ref
                        .read(prefetchSettingsProvider.notifier)
                        .setProfile(profile);
                  }
                },
              ),

              const SizedBox(height: 16),

              // Progress display (if active)
              if (progress.isActive || progress.canResume)
                _ProgressDisplay(progress: progress),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: progress.isActive || currentCenter == null
                          ? null
                          : () => _startPrefetch(context, ref, currentCenter!,
                              tileSource.id),
                      icon: const Icon(Icons.download_for_offline),
                      label: const Text('Prefetch Current View'),
                    ),
                  ),
                  if (progress.isActive) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        ref.read(prefetchActionsProvider).pause();
                      },
                      icon: const Icon(Icons.pause),
                      tooltip: 'Pause',
                    ),
                    IconButton(
                      onPressed: () {
                        ref.read(prefetchActionsProvider).cancel();
                      },
                      icon: const Icon(Icons.stop),
                      tooltip: 'Cancel',
                    ),
                  ],
                  if (progress.canResume) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        ref.read(prefetchActionsProvider).resume();
                      },
                      icon: const Icon(Icons.play_arrow),
                      tooltip: 'Resume',
                    ),
                  ],
                ],
              ),

              // Completion message
              if (progress.isFinished && progress.state != PrefetchState.idle)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _CompletionMessage(progress: progress),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _startPrefetch(
    BuildContext context,
    WidgetRef ref,
    LatLng center,
    String sourceId,
  ) async {
    try {
      await ref.read(prefetchActionsProvider).prefetchCurrentView(
            center: center,
            sourceId: sourceId,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Prefetch failed: $e')),
        );
      }
    }
  }
}

/// Progress display widget
class _ProgressDisplay extends StatelessWidget {
  final PrefetchProgress progress;

  const _ProgressDisplay({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: progress.queuedCount > 0
                  ? progress.progressPercent / 100
                  : null,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${progress.completedCount}/${progress.queuedCount} tiles',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${progress.progressPercent.toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (progress.tilesPerSecond > 0)
              Text(
                '${progress.tilesPerSecond.toStringAsFixed(1)} tiles/sec',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Completion message widget
class _CompletionMessage extends StatelessWidget {
  final PrefetchProgress progress;

  const _CompletionMessage({required this.progress});

  @override
  Widget build(BuildContext context) {
    final (icon, message, color) = switch (progress.state) {
      PrefetchState.completed => (
          Icons.check_circle,
          'Prefetch completed: ${progress.completedCount} tiles',
          Colors.green
        ),
      PrefetchState.cancelled => (
          Icons.cancel,
          'Prefetch cancelled',
          Colors.orange
        ),
      PrefetchState.failed => (
          Icons.error,
          'Prefetch failed: ${progress.errorMessage ?? "Unknown error"}',
          Colors.red
        ),
      _ => (Icons.info, '', Colors.grey),
    };

    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}
