import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_app_gps/app/app_router.dart';
import 'package:my_app_gps/core/utils/shared_prefs_holder.dart';
import 'package:my_app_gps/features/auth/controller/auth_notifier.dart';
import 'package:my_app_gps/features/auth/controller/auth_state.dart';
import 'package:my_app_gps/features/notifications/view/notification_badge.dart';
import 'package:my_app_gps/services/traccar_connection_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent notification toggle provider (default ON)
final notificationEnabledProvider = StateProvider<bool>((ref) {
  if (SharedPrefsHolder.isInitialized) {
    final prefs = SharedPrefsHolder.instance;
    return prefs.getBool('notifications_enabled') ?? true;
  }
  return true; // fallback when SharedPrefs not yet injected
});

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Optimized with .select() to limit rebuilds to username/avatar changes
    final username = ref.watch(
      authNotifierProvider.select(
        (s) => s is AuthAuthenticated ? s.email : null,
      ),
    );
    // Optimized with .select() for connection badge (only connected/connecting/retrying toggles)
    final connected = ref.watch(
      traccarConnectionStatusProvider.select(
        (s) => s == ConnectionStatus.connected,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          NotificationBadge(
            onTap: () => context.go(AppRoutes.alerts),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Account'),
            subtitle: Text(username ?? 'Not signed in'),
            trailing: Icon(
              connected ? Icons.cloud_done : Icons.cloud_off,
              color: connected ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          // Dev-only test notification tile removed per requirements.
          // Notifications toggle
          Consumer(
            builder: (context, ref, _) {
              final enabled = ref.watch(notificationEnabledProvider);
              return SwitchListTile.adaptive(
                value: enabled,
                onChanged: (value) async {
                  ref.read(notificationEnabledProvider.notifier).state = value;
                  final prefs = SharedPrefsHolder.isInitialized
                      ? SharedPrefsHolder.instance
                      : await SharedPreferences.getInstance();
                  await prefs.setBool('notifications_enabled', value);
                  debugPrint(
                      '[Settings] Notifications ${value ? 'enabled' : 'disabled'}',);
                },
                title: const Text('Notifications'),
                subtitle: const Text(
                  'Turn off to stop receiving live alerts. You can still view them in the Alerts tab.',
                ),
                secondary: const Icon(Icons.notifications),
                activeTrackColor: Colors.lightGreen,
              );
            },
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).logout();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Logged out')));
              }
              // GoRouter redirect will take user to login automatically based on auth state.
            },
          ),
        ],
      ),
    );
  }
}
