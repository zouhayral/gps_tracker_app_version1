import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_app_gps/app/app_router.dart';
import 'package:my_app_gps/core/navigation/safe_navigation.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/core/utils/shared_prefs_holder.dart';
import 'package:my_app_gps/features/auth/controller/auth_notifier.dart';
import 'package:my_app_gps/features/auth/controller/auth_state.dart';
import 'package:my_app_gps/features/localization/locale_provider.dart';
import 'package:my_app_gps/features/notifications/view/notification_badge.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';

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
    
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDarkMode ? theme.colorScheme.background : Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          t.settingsTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          NotificationBadge(
            onTap: () => context.safeGo(AppRoutes.alerts),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 100, // Extra padding for floating bottom nav bar
        ),
        children: [
          // User Profile Card
          _ModernCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Avatar
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.secondary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Username
                  Text(
                    username ?? t.notSignedIn,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Notifications Section
          _SectionHeader(title: t.notifications),
          _ModernCard(
            child: Consumer(
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
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.notifications_active,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.notifications,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              t.notificationsSubtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Analytics & Reports Section
          _SectionHeader(title: t.analyticsReports),
          _ModernCard(
            child: _ModernMenuItem(
              icon: Icons.analytics_outlined,
              iconColor: const Color(0xFFb4e15c),
              title: t.reportsTitle,
              subtitle: t.reportsSubtitle,
              onTap: () {
                AppLogger.debug('[Settings] Navigating to AnalyticsPage');
                context.safePush<void>(AppRoutes.analytics);
              },
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Geofence Management Section
          _SectionHeader(title: t.geofences),
          _ModernCard(
            child: _ModernMenuItem(
              icon: Icons.fence_outlined,
              iconColor: Colors.purple,
              title: t.manageGeofences,
              subtitle: t.manageGeofencesSubtitle,
              onTap: () => context.safePush<void>(AppRoutes.geofences),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Language Section
          _SectionHeader(title: t.language),
          _ModernCard(
            child: Consumer(
              builder: (context, ref, _) {
                final currentLocale = ref.watch(localeProvider);
                final localeName = ref.read(localeProvider.notifier).getLocaleName();
                
                return _ModernMenuItem(
                  icon: Icons.language,
                  iconColor: Colors.orange,
                  title: t.language,
                  subtitle: '${t.currentLanguage}: $localeName',
                  onTap: () async {
                    final selectedLocale = await showDialog<Locale>(
                      context: context,
                      builder: (context) => _ModernLanguageDialog(
                        currentLocale: currentLocale,
                      ),
                    );
                    
                    if (selectedLocale != null && selectedLocale != currentLocale) {
                      await ref.read(localeProvider.notifier).setLocale(selectedLocale);
                    }
                  },
                );
              },
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Logout Button
          _ModernCard(
            color: Colors.red.shade50,
            child: InkWell(
              onTap: () async {
                await ref.read(authNotifierProvider.notifier).logout();
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(t.loggedOut)));
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.logout,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      t.logout,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// Modern Card Widget
class _ModernCard extends StatelessWidget {
  const _ModernCard({
    required this.child,
    this.color,
  });

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: color ?? (isDarkMode ? Colors.grey[850] : Colors.white),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// Section Header Widget
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
    );
  }
}

// Modern Menu Item Widget
class _ModernMenuItem extends StatelessWidget {
  const _ModernMenuItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }
}

// Modern Language Dialog
class _ModernLanguageDialog extends StatelessWidget {
  const _ModernLanguageDialog({required this.currentLocale});

  final Locale currentLocale;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.language,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    t.selectLanguage,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _LanguageOption(
              locale: const Locale('en'),
              name: 'English',
              flag: '🇬🇧',
              currentLocale: currentLocale,
            ),
            const Divider(height: 24),
            _LanguageOption(
              locale: const Locale('fr'),
              name: 'Français',
              flag: '🇫🇷',
              currentLocale: currentLocale,
            ),
            const Divider(height: 24),
            _LanguageOption(
              locale: const Locale('ar'),
              name: 'العربية',
              flag: '🇸🇦',
              currentLocale: currentLocale,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(t.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Language option widget for the language selector dialog
class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.locale,
    required this.name,
    required this.flag,
    required this.currentLocale,
  });

  final Locale locale;
  final String name;
  final String flag;
  final Locale currentLocale;

  @override
  Widget build(BuildContext context) {
    final isSelected = locale.languageCode == currentLocale.languageCode;
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: () => Navigator.pop(context, locale),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? theme.colorScheme.primary 
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Text(
              flag,
              style: const TextStyle(fontSize: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 16,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
