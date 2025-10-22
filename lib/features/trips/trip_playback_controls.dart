import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/providers/trip_providers.dart';

/// Placeholder playback controls for trip replay. Wires into tripPlaybackProvider.
class TripPlaybackControls extends ConsumerWidget {
  const TripPlaybackControls({super.key, this.onTogglePlay, this.onSeek});

  final void Function({required bool isPlaying})? onTogglePlay;
  final void Function(double progress)? onSeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tripPlaybackProvider);
    final notifier = ref.read(tripPlaybackProvider.notifier);

    return Row(
      children: [
        IconButton(
          icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: () {
            if (state.isPlaying) {
              notifier.pause();
              onTogglePlay?.call(isPlaying: false);
            } else {
              notifier.play();
              onTogglePlay?.call(isPlaying: true);
            }
          },
        ),
        Expanded(
          child: Slider(
            value: state.progress,
            onChanged: (v) {
              notifier.seek(v);
              onSeek?.call(v);
            },
          ),
        ),
        Text('${(state.progress * 100).toStringAsFixed(0)}%'),
      ],
    );
  }
}
