import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/features/map/view/map_page.dart';

/// Thin wrapper to expose the Map feature inside Dashboard routes/navigation.
class MapsScreen extends ConsumerWidget {
  const MapsScreen({super.key, this.preselectedIds});

  /// Optional list of device IDs to focus/select on open.
  final Set<int>? preselectedIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MapPage(preselectedIds: preselectedIds);
  }
}
