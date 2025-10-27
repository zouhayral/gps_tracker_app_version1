import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/providers/notification_providers.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';

/// NotificationActionBar provides a single "Mark all read" action.
/// All filter controls have been removed as per the latest requirements.
class NotificationActionBar extends ConsumerWidget {
  const NotificationActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    return Container(
      color: const Color(0xFFF5FFE2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildMarkAllReadChip(context, ref, t),
          const SizedBox(width: 12),
          _buildDeleteAllChip(context, ref, t),
        ],
      ),
    );
  }

  Widget _buildMarkAllReadChip(BuildContext context, WidgetRef ref, AppLocalizations t) {
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
              t.markAll,
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

  Widget _buildDeleteAllChip(BuildContext context, WidgetRef ref, AppLocalizations t) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.deleteAllNotifications),
            content: Text(t.deleteAllNotificationsConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(t.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                child: Text(t.deleteAll),
              ),
            ],
          ),
        );
        if (confirmed ?? false) {
          await ref.read(clearAllNotificationsProvider.future);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t.allNotificationsDeleted)),
            );
          }
        }
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
              Icons.delete_forever_rounded,
              size: 18,
              color: Colors.redAccent.shade200,
            ),
            const SizedBox(width: 6),
            Text(
              t.deleteAll,
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
