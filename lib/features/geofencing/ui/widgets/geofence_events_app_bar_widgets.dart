import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_events_filter_providers.dart';

/// Sort menu button widget for geofence events
class SortMenuButton extends ConsumerWidget {
  const SortMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(geofenceEventsFilterProvider);
    final filterNotifier = ref.read(geofenceEventsFilterProvider.notifier);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.sort),
      tooltip: 'Sort',
      onSelected: (value) => filterNotifier.setSortBy(value),
      itemBuilder: (context) => [
        _buildSortMenuItem(
          context,
          'timestamp',
          Icons.schedule,
          'By Time',
          filterState.sortBy == 'timestamp',
          filterState.sortAscending,
        ),
        _buildSortMenuItem(
          context,
          'type',
          Icons.category,
          'By Type',
          filterState.sortBy == 'type',
          filterState.sortAscending,
        ),
        _buildSortMenuItem(
          context,
          'status',
          Icons.flag,
          'By Status',
          filterState.sortBy == 'status',
          filterState.sortAscending,
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildSortMenuItem(
    BuildContext context,
    String value,
    IconData icon,
    String label,
    bool isSelected,
    bool isAscending,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Text(label),
          if (isSelected) ...[
            const Spacer(),
            Icon(
              isAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
            ),
          ],
        ],
      ),
    );
  }
}

/// More actions menu widget
class MoreActionsMenu extends StatelessWidget {
  final VoidCallback onAcknowledgeAll;
  final VoidCallback onArchiveOld;
  final VoidCallback onExport;

  const MoreActionsMenu({
    required this.onAcknowledgeAll,
    required this.onArchiveOld,
    required this.onExport,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      icon: const Icon(Icons.more_vert),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'acknowledge_all',
          child: Row(
            children: [
              Icon(Icons.check_circle),
              SizedBox(width: 8),
              Text('Acknowledge All'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'archive_old',
          child: Row(
            children: [
              Icon(Icons.archive),
              SizedBox(width: 8),
              Text('Archive Old Events'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(Icons.download),
              SizedBox(width: 8),
              Text('Export Events'),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'acknowledge_all':
            onAcknowledgeAll();
          case 'archive_old':
            onArchiveOld();
          case 'export':
            onExport();
        }
      },
    );
  }
}
