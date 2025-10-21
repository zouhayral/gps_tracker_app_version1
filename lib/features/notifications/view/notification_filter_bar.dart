import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/providers/notification_providers.dart';

/// NotificationActionBar provides a single "Mark all read" action.
/// All filter controls have been removed as per the latest requirements.
class NotificationActionBar extends ConsumerWidget {
  const NotificationActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: const Color(0xFFF5FFE2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _buildMarkAllReadChip(context, ref),
      ),
    );
  }

  Widget _buildMarkAllReadChip(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: () async {
        // Mark all as read
        await ref.read(markAllAsReadProvider.future);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: Colors.grey.shade400,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.done_all,
              size: 18,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 6),
            Text(
              'Mark all read',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
