import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/app/app_router.dart';
import 'package:my_app_gps/core/navigation/safe_navigation.dart';
import 'package:my_app_gps/core/utils/shared_prefs_holder.dart';
import 'package:my_app_gps/features/auth/controller/auth_notifier.dart';
import 'package:my_app_gps/features/auth/controller/auth_state.dart';
import 'package:my_app_gps/features/geofencing/models/geofence_optimizer_state.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_optimizer_provider.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_permission_provider.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';
import 'package:my_app_gps/features/geofencing/ui/widgets/permission_prompt_dialog.dart';
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
            onTap: () => context.safeGo(AppRoutes.alerts),
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
          const Divider(height: 32),
          // === Geofence Configuration Section ===
          const ListTile(
            title: Text(
              'Geofences',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            dense: true,
          ),
          ListTile(
            leading: const Icon(Icons.fence_outlined),
            title: const Text('Manage Geofences'),
            subtitle: const Text('Create, edit, or delete geofences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.safePush<void>(AppRoutes.geofences),
          ),
          Consumer(
            builder: (context, ref, _) {
              // Watch the async monitor service
              final monitorServiceAsync = ref.watch(geofenceMonitorServiceProvider);
              
              // Get authenticated user for starting monitoring
              final authState = ref.watch(authNotifierProvider);
              final userId = authState is AuthAuthenticated 
                  ? authState.email 
                  : null;
              
              // Only try to access monitor state if service is initialized
              final isActive = monitorServiceAsync.maybeWhen(
                data: (service) {
                  try {
                    final monitorState = ref.watch(geofenceMonitorProvider);
                    return monitorState.isActive;
                  } catch (e) {
                    // Service not yet fully initialized
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
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Geofence monitoring started'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } else {
                      await controller.stop();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('⏸️ Geofence monitoring stopped'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('❌ Failed to ${value ? "start" : "stop"} monitoring: $e'),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                },
                title: const Text('Enable Geofencing'),
                subtitle: Text(
                  userId == null
                      ? 'Sign in to enable geofence monitoring'
                      : 'Turn on background geofence monitoring and notifications',
                ),
                secondary: const Icon(Icons.my_location),
                activeTrackColor: Colors.lightGreen,
              );
            },
          ),
          // === Background Access Toggle ===
          Consumer(
            builder: (context, ref, _) {
              final permActions = ref.read(permissionActionsProvider);
              final hasBackground = ref.watch(hasBackgroundPermissionProvider);
              final isPermanentlyDenied = ref.watch(isPermissionPermanentlyDeniedProvider);
              
              return Column(
                children: [
                  ListTile(
                    leading: Icon(
                      hasBackground ? Icons.security_rounded : Icons.security_update_warning_rounded,
                      color: hasBackground ? Colors.green : Colors.orange,
                    ),
                    title: const Text('Background Access'),
                    subtitle: Text(
                      hasBackground
                          ? 'Background geofence monitoring enabled'
                          : 'Limited to foreground monitoring',
                      style: TextStyle(
                        color: hasBackground ? Colors.green.shade700 : Colors.orange.shade700,
                      ),
                    ),
                    trailing: Switch(
                      value: hasBackground,
                      onChanged: (v) async {
                        if (v) {
                          // User wants to enable background access
                          final granted = await permActions.requestBackground();
                          
                          if (!granted && context.mounted) {
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
                          } else if (granted && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Background access granted'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        } else {
                          // User toggled off background access
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('⚠️ Foreground-only mode activated'),
                                duration: Duration(seconds: 2),
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
                            title: const Text('About Foreground Mode'),
                            content: const Text(
                              'In foreground-only mode, geofence monitoring works only while '
                              'the app is open. To receive alerts when the app is closed, '
                              'enable background location access.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => context.safePop<void>(),
                                child: const Text('Got it'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
          // === Adaptive Optimization Toggle ===
          Consumer(
            builder: (context, ref, _) {
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
                  modeText = 'Optimization disabled';
                  break;
                case OptimizationMode.active:
                  modeIcon = Icons.bolt_rounded;
                  modeColor = Colors.green;
                  modeText = 'Active mode (${currentInterval}s interval)';
                  break;
                case OptimizationMode.idle:
                  modeIcon = Icons.snooze_rounded;
                  modeColor = Colors.orange;
                  modeText = 'Idle mode (${currentInterval}s interval)';
                  break;
                case OptimizationMode.batterySaver:
                  modeIcon = Icons.battery_saver_rounded;
                  modeColor = Colors.red;
                  modeText = 'Battery saver (${currentInterval}s interval)';
                  break;
              }
              
              return Column(
                children: [
                  ListTile(
                    leading: Icon(modeIcon, color: modeColor),
                    title: const Text('Adaptive Optimization'),
                    subtitle: Text(
                      isActive ? modeText : 'Disabled - Fixed evaluation frequency',
                      style: TextStyle(
                        color: isActive ? modeColor : Colors.grey,
                      ),
                    ),
                    trailing: Switch(
                      value: isActive,
                      onChanged: (v) async {
                        if (v) {
                          try {
                            await optimizerActions.start();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ Adaptive optimization enabled'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('❌ Failed to start optimizer: $e'),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          }
                        } else {
                          await optimizerActions.stop();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('⏸️ Adaptive optimization disabled'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
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
                              Icon(Icons.insights_rounded, size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Optimization Statistics',
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
                              label: 'Savings: ${savingsPercent.toStringAsFixed(1)}%',
                              color: Colors.green,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Default Notification Type'),
            subtitle: const Text('Local only'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🚧 Coming soon: Change notification type (Local/Push/Both)'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_suggest_outlined),
            title: const Text('Evaluation Frequency'),
            subtitle: const Text('Balanced (recommended)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🚧 Coming soon: Adjust evaluation interval (Fast/Balanced/Battery Saver)'),
                  duration: Duration(seconds: 3),
                ),
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
