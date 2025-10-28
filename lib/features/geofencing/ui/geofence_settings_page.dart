import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/navigation/safe_navigation.dart';
import 'package:my_app_gps/core/utils/shared_prefs_holder.dart';
import 'package:my_app_gps/features/auth/controller/auth_notifier.dart';
import 'package:my_app_gps/features/auth/controller/auth_state.dart';
import 'package:my_app_gps/features/geofencing/models/geofence_optimizer_state.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_optimizer_provider.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_permission_provider.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';
import 'package:my_app_gps/features/geofencing/ui/widgets/permission_prompt_dialog.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Consolidated Geofence Settings Page
///
/// This page contains all geofence-related configuration options:
/// - Enable/Disable Geofencing
/// - Background Access Permission
/// - Adaptive Optimization
/// - Default Notification Type
/// - Evaluation Frequency
///
/// ## Navigation
/// Route: `/geofences/settings`
/// Accessible from: GeofenceListPage → Settings icon
///
/// ## Example Usage in GoRouter
/// ```dart
/// GoRoute(
///   path: '/geofences/settings',
///   name: 'geofence-settings',
///   builder: (context, state) => const GeofenceSettingsPage(),
/// ),
/// ```
class GeofenceSettingsPage extends ConsumerStatefulWidget {
  const GeofenceSettingsPage({super.key});

  @override
  ConsumerState<GeofenceSettingsPage> createState() =>
      _GeofenceSettingsPageState();
}

class _GeofenceSettingsPageState extends ConsumerState<GeofenceSettingsPage> {
  // Local state for settings not yet persisted
  String _notificationType = 'Local only';
  String _evaluationMode = 'Balanced (recommended)';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// Load saved settings from SharedPreferences
  Future<void> _loadSettings() async {
    final prefs = SharedPrefsHolder.isInitialized
        ? SharedPrefsHolder.instance
        : await SharedPreferences.getInstance();

    setState(() {
      _notificationType = prefs.getString('geofence_notification_type') ?? 'Local only';
      _evaluationMode = prefs.getString('geofence_evaluation_mode') ?? 'Balanced (recommended)';
    });
  }

  /// Save notification type preference
  Future<void> _saveNotificationType(String type) async {
    final prefs = SharedPrefsHolder.isInitialized
        ? SharedPrefsHolder.instance
        : await SharedPreferences.getInstance();
    await prefs.setString('geofence_notification_type', type);
    setState(() {
      _notificationType = type;
    });
  }

  /// Save evaluation mode preference
  Future<void> _saveEvaluationMode(String mode) async {
    final prefs = SharedPrefsHolder.isInitialized
        ? SharedPrefsHolder.instance
        : await SharedPreferences.getInstance();
    await prefs.setString('geofence_evaluation_mode', mode);
    setState(() {
      _evaluationMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t?.geofenceSettings ?? 'Geofence Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: t?.aboutGeofenceSettings ?? 'About Geofence Settings',
            onPressed: () => _showAboutDialog(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header card with description
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.settings_applications,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          t?.geofenceConfiguration ?? 'Geofence Configuration',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t?.configureHowGeofencesWork ?? 'Configure how geofences work, including monitoring, notifications, and performance optimization.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // === Enable Geofencing ===
          _buildEnableGeofencingSection(context, t),
          const Divider(height: 32),

          // === Background Access ===
          _buildBackgroundAccessSection(context, t),
          const Divider(height: 32),

          // === Adaptive Optimization ===
          _buildAdaptiveOptimizationSection(context, t),
          const Divider(height: 32),

          // === Default Notification Type ===
          _buildNotificationTypeSection(context, t),
          const Divider(height: 32),

          // === Evaluation Frequency ===
          _buildEvaluationFrequencySection(context, t),
          const SizedBox(height: 24),

          // === Reset to Defaults Button ===
          OutlinedButton.icon(
            icon: const Icon(Icons.restore),
            label: Text(t?.resetToDefaults ?? 'Reset to Defaults'),
            onPressed: () => _resetToDefaults(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // SECTION BUILDERS
  // ==========================================================================

  /// Enable Geofencing section
  Widget _buildEnableGeofencingSection(BuildContext context, AppLocalizations? t) {
    final monitorServiceAsync = ref.watch(geofenceMonitorServiceProvider);
    final authState = ref.watch(authNotifierProvider);
    final userId = authState is AuthAuthenticated ? authState.email : null;

    final isActive = monitorServiceAsync.maybeWhen(
      data: (service) {
        try {
          final monitorState = ref.watch(geofenceMonitorProvider);
          return monitorState.isActive;
        } catch (e) {
          return false;
        }
      },
      orElse: () => false,
    );

    return SwitchListTile.adaptive(
      value: isActive,
      onChanged: userId == null || !monitorServiceAsync.hasValue
          ? null
          : (value) async {
              try {
                final controller = ref.read(geofenceMonitorProvider.notifier);
                if (value) {
                  await controller.start(userId);
                  if (!context.mounted) return;
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(t?.geofenceMonitoringStarted ?? '✅ Geofence monitoring started'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } else {
                  await controller.stop();
                  if (!context.mounted) return;
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(t?.geofenceMonitoringStopped ?? '⏸️ Geofence monitoring stopped'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                }
              } catch (e) {
                if (!context.mounted) return;
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(value 
                        ? (t?.failedToStartMonitoring ?? '❌ Failed to start monitoring: $e')
                        : (t?.failedToStopMonitoring ?? '❌ Failed to stop monitoring: $e')),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
      title: Text(t?.enableGeofencing ?? 'Enable Geofencing'),
      subtitle: Text(
        userId == null
            ? (t?.signInToEnableGeofenceMonitoring ?? 'Sign in to enable geofence monitoring')
            : isActive
                ? (t?.backgroundGeofenceMonitoringActive ?? 'Background geofence monitoring and notifications are active')
                : (t?.turnOnToReceiveAlerts ?? 'Turn on to receive alerts when entering or exiting geofences'),
      ),
      secondary: const Icon(Icons.my_location),
      activeTrackColor: Colors.lightGreen,
    );
  }

  /// Background Access section
  Widget _buildBackgroundAccessSection(BuildContext context, AppLocalizations? t) {
    final permActions = ref.read(permissionActionsProvider);
    final hasBackground = ref.watch(hasBackgroundPermissionProvider);
    final isPermanentlyDenied = ref.watch(isPermissionPermanentlyDeniedProvider);

    return Column(
      children: [
        ListTile(
          leading: Icon(
            hasBackground
                ? Icons.security_rounded
                : Icons.security_update_warning_rounded,
            color: hasBackground ? Colors.green : Colors.orange,
          ),
          title: Text(t?.backgroundAccess ?? 'Background Access'),
          subtitle: Text(
            hasBackground
                ? (t?.backgroundGeofenceMonitoringEnabled ?? 'Background geofence monitoring enabled')
                : (t?.disabledAppMayMissEvents ?? 'Disabled – app may miss events when closed'),
            style: TextStyle(
              color: hasBackground ? Colors.green.shade700 : Colors.orange.shade700,
            ),
          ),
          trailing: Switch(
            value: hasBackground,
            activeTrackColor: Colors.lightGreen,
            onChanged: (v) async {
              if (v) {
                // User wants to enable background access
                final granted = await permActions.requestBackground();

                if (!context.mounted) return;
                if (!granted && mounted) {
                  // Show education dialog if denied
                  await showDialog<void>(
                    context: context,
                    builder: (_) => PermissionPromptDialog(
                      onOpenSettings: () async {
                        await permActions.openSettings();
                        // Refresh after returning from settings
                        await Future<void>.delayed(const Duration(seconds: 1));
                        await permActions.refresh();
                      },
                    ),
                  );
                } else if (granted && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(t?.backgroundAccessGranted ?? '✅ Background access granted'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } else {
                // User toggled off background access
                if (!context.mounted) return;
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(t?.foregroundOnlyModeActivated ?? '⚠️ Foreground-only mode activated'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
          ),
        ),

        // Show banner if permanently denied
        if (isPermanentlyDenied)
          PermissionPromptBanner(
            onOpenSettings: () async {
              await permActions.openSettings();
              await Future<void>.delayed(const Duration(seconds: 1));
              await permActions.refresh();
            },
          )
        // Show foreground-only banner if denied but not permanently
        else if (!hasBackground)
          ForegroundOnlyBanner(
            onLearnMore: () {
              showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(t?.aboutForegroundMode ?? 'About Foreground Mode'),
                  content: Text(
                    t?.inForegroundOnlyMode ?? 'In foreground-only mode, geofence monitoring works only while '
                    'the app is open. To receive alerts when the app is closed, '
                    'enable background location access.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => context.safePop<void>(),
                      child: Text(t?.gotIt ?? 'Got it'),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  /// Adaptive Optimization section
  Widget _buildAdaptiveOptimizationSection(BuildContext context, AppLocalizations? t) {
    final optimizerActions = ref.read(optimizerActionsProvider);
    final isActive = ref.watch(isOptimizerActiveProvider);
    final mode = ref.watch(optimizationModeProvider);
    final batteryStatus = ref.watch(batteryStatusProvider);
    final motionStatus = ref.watch(motionStatusProvider);
    final currentInterval = ref.watch(currentIntervalProvider);
    final savingsPercent = ref.watch(batterySavingsPercentProvider);

    // Determine icon and color based on mode
    IconData modeIcon;
    Color? modeColor;
    String modeText;

    switch (mode) {
      case OptimizationMode.disabled:
        modeIcon = Icons.bolt_rounded;
        modeColor = Colors.grey;
        modeText = t?.optimizationDisabled ?? 'Optimization disabled';
      case OptimizationMode.active:
        modeIcon = Icons.bolt_rounded;
        modeColor = Colors.green;
        modeText = '${t?.activeMode ?? 'Active mode'} (${currentInterval}s ${t?.interval ?? 'interval'})';
      case OptimizationMode.idle:
        modeIcon = Icons.snooze_rounded;
        modeColor = Colors.orange;
        modeText = '${t?.idleMode ?? 'Idle mode'} (${currentInterval}s ${t?.interval ?? 'interval'})';
      case OptimizationMode.batterySaver:
        modeIcon = Icons.battery_saver_rounded;
        modeColor = Colors.red;
        modeText = '${t?.batterySaver ?? 'Battery saver'} (${currentInterval}s ${t?.interval ?? 'interval'})';
    }

    return Column(
      children: [
        ListTile(
          leading: Icon(modeIcon, color: modeColor),
          title: Text(t?.adaptiveOptimization ?? 'Adaptive Optimization'),
          subtitle: Text(
            isActive
                ? modeText
                : (t?.disabledFixedEvaluationFrequency ?? 'Disabled - Fixed evaluation frequency'),
            style: TextStyle(
              color: isActive ? modeColor : Colors.grey,
            ),
          ),
          trailing: Switch(
            value: isActive,
            activeTrackColor: Colors.lightGreen,
            onChanged: (v) async {
              if (v) {
                try {
                  await optimizerActions.start();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(t?.adaptiveOptimizationEnabled ?? '✅ Adaptive optimization enabled'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${t?.failedToStartOptimizer ?? '❌ Failed to start optimizer'}: $e'),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } else {
                await optimizerActions.stop();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t?.adaptiveOptimizationDisabled ?? '⏸️ Adaptive optimization disabled'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ),

        // Show optimizer stats when active
        if (isActive)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.insights_rounded,
                        size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(
                      t?.optimizationStatistics ?? 'Optimization Statistics',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        icon: Icons.battery_charging_full_rounded,
                        label: batteryStatus,
                        color: Colors.green,
                      ),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        icon: Icons.directions_walk_rounded,
                        label: motionStatus,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                if (savingsPercent > 0) ...[
                  const SizedBox(height: 8),
                  _buildStatItem(
                    icon: Icons.eco_rounded,
                    label: '${t?.savings ?? 'Savings'}: ${savingsPercent.toStringAsFixed(1)}%',
                    color: Colors.green,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// Default Notification Type section
  Widget _buildNotificationTypeSection(BuildContext context, AppLocalizations? t) {
    return ListTile(
      leading: const Icon(Icons.notifications_active_outlined),
      title: Text(t?.defaultNotificationType ?? 'Default Notification Type'),
      subtitle: Text(_notificationType),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showNotificationTypePicker(context),
    );
  }

  /// Evaluation Frequency section
  Widget _buildEvaluationFrequencySection(BuildContext context, AppLocalizations? t) {
    return ListTile(
      leading: const Icon(Icons.settings_suggest_outlined),
      title: Text(t?.evaluationFrequency ?? 'Evaluation Frequency'),
      subtitle: Text(_evaluationMode),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showEvaluationFrequencyPicker(context),
    );
  }

  // ==========================================================================
  // HELPER METHODS
  // ==========================================================================

  /// Show notification type picker
  Future<void> _showNotificationTypePicker(BuildContext context) async {
    final types = ['Local only', 'Push only', 'Both (Local + Push)', 'Silent'];
    final descriptions = {
      'Local only': 'Show notifications only on this device',
      'Push only': 'Send push notifications via server (requires network)',
      'Both (Local + Push)': 'Send both local and push notifications',
      'Silent': 'No notifications (events still logged)',
    };

    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Notification Type',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            ...types.map((type) => ListTile(
                  title: Text(type),
                  subtitle: Text(
                    descriptions[type] ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  selected: type == _notificationType,
                  leading: Icon(
                    type == _notificationType
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  onTap: () => Navigator.pop(context, type),
                )),
          ],
        ),
      ),
    );

    if (result != null) {
      await _saveNotificationType(result);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Notification type set to: $result'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Show evaluation frequency picker
  Future<void> _showEvaluationFrequencyPicker(BuildContext context) async {
    final modes = [
      'Fast (Real-time)',
      'Balanced (recommended)',
      'Battery Saver'
    ];
    final descriptions = {
      'Fast (Real-time)': 'Check every 5-10s (high battery usage)',
      'Balanced (recommended)': 'Check every 30s (moderate battery usage)',
      'Battery Saver': 'Check every 60-120s (low battery usage)',
    };

    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Evaluation Frequency',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            ...modes.map((mode) => ListTile(
                  title: Text(mode),
                  subtitle: Text(
                    descriptions[mode] ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  selected: mode == _evaluationMode,
                  leading: Icon(
                    mode == _evaluationMode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  onTap: () => Navigator.pop(context, mode),
                )),
          ],
        ),
      ),
    );

    if (result != null) {
      await _saveEvaluationMode(result);
      if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Evaluation frequency set to: $result'),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  /// Reset all settings to defaults
  Future<void> _resetToDefaults(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'This will reset all geofence settings to their default values. '
          'Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    if (confirm ?? false) {
      await _saveNotificationType('Local only');
      await _saveEvaluationMode('Balanced (recommended)');

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Settings reset to defaults'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Show about dialog
  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Geofence Settings'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAboutItem(
                'Enable Geofencing',
                'Controls the main geofence monitoring service. When disabled, '
                'no geofence events will be detected.',
              ),
              const SizedBox(height: 12),
              _buildAboutItem(
                'Background Access',
                'Allows the app to detect geofence events even when closed. '
                'Without this permission, monitoring only works while app is open.',
              ),
              const SizedBox(height: 12),
              _buildAboutItem(
                'Adaptive Optimization',
                'Automatically adjusts geofence check frequency based on battery '
                'level and device motion to save power.',
              ),
              const SizedBox(height: 12),
              _buildAboutItem(
                'Notification Type',
                'Choose how you want to be notified about geofence events. '
                'Local notifications work offline, push requires network.',
              ),
              const SizedBox(height: 12),
              _buildAboutItem(
                'Evaluation Frequency',
                'How often the app checks if devices are inside geofences. '
                'Higher frequency = more battery usage but faster detection.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.safePop<void>(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Build about item helper
  Widget _buildAboutItem(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }

  /// Helper widget for optimizer statistics display
  static Widget _buildStatItem({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
