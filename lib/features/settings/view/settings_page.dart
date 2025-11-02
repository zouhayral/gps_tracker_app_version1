import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/app/app_router.dart';
import 'package:my_app_gps/core/navigation/safe_navigation.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/core/utils/shared_prefs_holder.dart';
import 'package:my_app_gps/features/auth/controller/auth_notifier.dart';
import 'package:my_app_gps/features/auth/controller/auth_state.dart';
import 'package:my_app_gps/features/localization/locale_provider.dart';
import 'package:my_app_gps/features/notifications/view/notification_badge.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';
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
    final t = AppLocalizations.of(context)!;
    
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
        title: Text(t.settingsTitle),
        actions: [
          NotificationBadge(
            onTap: () => context.safeGo(AppRoutes.alerts),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: Text(t.account),
            subtitle: Text(username ?? t.notSignedIn),
            trailing: Icon(
              connected ? Icons.cloud_done : Icons.cloud_off,
              color: connected ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(height: 8),
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
                title: Text(t.notifications),
                subtitle: Text(t.notificationsSubtitle),
                secondary: const Icon(Icons.notifications),
                activeTrackColor: Colors.lightGreen,
              );
            },
          ),
          const Divider(height: 32),
          // === Analytics & Reports Section ===
          ListTile(
            title: Text(
              t.analyticsReports,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            dense: true,
          ),
          ListTile(
            leading: const Icon(
              Icons.analytics_outlined,
              color: Color(0xFFb4e15c),
            ),
            title: Text(t.reportsTitle),
            subtitle: Text(t.reportsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              AppLogger.debug('[Settings] Navigating to AnalyticsPage');
              context.safePush<void>(AppRoutes.analytics);
            },
          ),
          const Divider(height: 32),
          // === Geofence Management Section ===
          ListTile(
            title: Text(
              t.geofences,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            dense: true,
          ),
          ListTile(
            leading: const Icon(Icons.fence_outlined),
            title: Text(t.manageGeofences),
            subtitle: Text(t.manageGeofencesSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.safePush<void>(AppRoutes.geofences),
          ),
          const Divider(height: 32),
          // === Localization Test Section ===
          ListTile(
            title: Text(
              t.languageDeveloperTools,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            dense: true,
          ),
          // Language Selector
          Consumer(
            builder: (context, ref, _) {
              final currentLocale = ref.watch(localeProvider);
              final localeName = ref.read(localeProvider.notifier).getLocaleName();
              
              return ListTile(
                leading: const Icon(Icons.language, color: Colors.orange),
                title: Text(t.language),
                subtitle: Text('${t.currentLanguage}: $localeName'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final selectedLocale = await showDialog<Locale>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(t.selectLanguage),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LanguageOption(
                            locale: const Locale('en'),
                            name: 'English',
                            currentLocale: currentLocale,
                          ),
                          const Divider(),
                          _LanguageOption(
                            locale: const Locale('fr'),
                            name: 'Français',
                            currentLocale: currentLocale,
                          ),
                          const Divider(),
                          _LanguageOption(
                            locale: const Locale('ar'),
                            name: 'العربية',
                            currentLocale: currentLocale,
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(t.cancel),
                        ),
                      ],
                    ),
                  );
                  
                  if (selectedLocale != null && selectedLocale != currentLocale) {
                    await ref.read(localeProvider.notifier).setLocale(selectedLocale);
                  }
                },
              );
            },
          ),
          const Divider(height: 32),
          // === Logout Section ===
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
            label: Text(t.logout),
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).logout();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(t.loggedOut)));
              }
              // GoRouter redirect will take user to login automatically based on auth state.
            },
          ),
        ],
      ),
    );
  }
}

/// Language option widget for the language selector dialog
class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.locale,
    required this.name,
    required this.currentLocale,
  });

  final Locale locale;
  final String name;
  final Locale currentLocale;

  @override
  Widget build(BuildContext context) {
    final isSelected = locale.languageCode == currentLocale.languageCode;
    
    return ListTile(
      leading: Radio<String>(
        value: locale.languageCode,
        groupValue: currentLocale.languageCode,
        onChanged: (_) => Navigator.pop(context, locale),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Theme.of(context).primaryColor : null,
        ),
      ),
      onTap: () => Navigator.pop(context, locale),
    );
  }
}
