import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';
import 'package:my_app_gps/services/notification_service.dart';

/// Diagnostic page for troubleshooting geofence notification issues
///
/// This page helps identify why notifications may not be appearing:
/// - Shows bridge attachment status
/// - Lists geofences with their trigger settings
/// - Displays monitoring state
/// - Shows recent events
/// - Provides test notification button
class GeofenceDiagnosticsPage extends ConsumerWidget {
  const GeofenceDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridgeAsync = ref.watch(geofenceNotificationBridgeProvider);
    final geofencesAsync = ref.watch(geofencesProvider);
    final monitorState = ref.watch(geofenceMonitorProvider);
    final eventsAsync = ref.watch(geofenceEventsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Geofence Diagnostics'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Bridge Status
          _buildSection(
            'Notification Bridge Status',
            bridgeAsync.when(
              data: (bridge) => _buildSuccessCard(
                '✅ Bridge Initialized',
                'Attached: ${bridge.isAttached}',
              ),
              loading: () => _buildWarningCard(
                '⏳ Bridge Loading',
                'Waiting for repositories to initialize...',
              ),
              error: (error, stack) => _buildErrorCard(
                '❌ Bridge Failed',
                'Error: $error',
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Monitoring Status
          _buildSection(
            'Monitor Service',
            monitorState.isActive
                ? _buildSuccessCard(
                    '✅ Monitoring Active',
                    'Active geofences: ${monitorState.activeGeofences}\n'
                    'Events triggered: ${monitorState.eventsTriggered}\n'
                    'Last update: ${monitorState.lastUpdate?.toString() ?? "Never"}',
                  )
                : _buildWarningCard(
                    '⚠️ Monitoring Inactive',
                    'Start monitoring to detect geofence events',
                  ),
          ),

          const SizedBox(height: 16),

          // Geofences with trigger settings
          _buildSection(
            'Geofences Configuration',
            geofencesAsync.when(
              data: (geofences) {
                if (geofences.isEmpty) {
                  return _buildWarningCard(
                    '⚠️ No Geofences',
                    'Create a geofence first',
                  );
                }

                return Column(
                  children: geofences.map((g) {
                    final hasIssues = !g.enabled || (!g.onEnter && !g.onExit);
                    
                    return Card(
                      color: hasIssues ? Colors.orange.shade50 : Colors.green.shade50,
                      child: ListTile(
                        leading: Icon(
                          hasIssues ? Icons.warning : Icons.check_circle,
                          color: hasIssues ? Colors.orange : Colors.green,
                        ),
                        title: Text(g.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Enabled: ${g.enabled}'),
                            Text('On Enter: ${g.onEnter} ${g.onEnter ? "✅" : "❌"}'),
                            Text('On Exit: ${g.onExit} ${g.onExit ? "✅" : "❌"}'),
                            Text('Notification: ${g.notificationType}'),
                          ],
                        ),
                        trailing: hasIssues
                            ? const Tooltip(
                                message: "This geofence won't trigger notifications",
                                child: Icon(Icons.error_outline, color: Colors.orange),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (e, s) => _buildErrorCard('Error', e.toString()),
            ),
          ),

          const SizedBox(height: 16),

          // Recent Events
          _buildSection(
            'Recent Events',
            eventsAsync.when(
              data: (events) {
                final recent = events.take(5).toList();
                if (recent.isEmpty) {
                  return _buildWarningCard(
                    '⚠️ No Events Yet',
                    'Enter or exit a geofence to test',
                  );
                }

                return Column(
                  children: recent.map((e) {
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          e.eventType == 'entry'
                              ? Icons.login
                              : e.eventType == 'exit'
                                  ? Icons.logout
                                  : Icons.timer,
                          color: e.eventType == 'entry'
                              ? Colors.green
                              : e.eventType == 'exit'
                                  ? Colors.red
                                  : Colors.orange,
                        ),
                        title: Text(e.geofenceName),
                        subtitle: Text(
                          '${e.eventType.toUpperCase()} - ${e.timestamp}',
                        ),
                        trailing: Text(e.status),
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (e, s) => _buildErrorCard('Error', e.toString()),
            ),
          ),

          const SizedBox(height: 16),

          // Test Notification Button
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Test Notification',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Send a test geofence notification to verify '
                    'notifications are working',
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final notificationService = ref.read(notificationServiceProvider);
                        
                        final now = DateTime.now();
                        
                        // Create a test event using factory constructor
                        final testEvent = GeofenceEvent.entry(
                          id: 'test_${now.millisecondsSinceEpoch}',
                          geofenceId: 'test',
                          geofenceName: 'Test Geofence',
                          deviceId: 'test-device',
                          deviceName: 'Test Device',
                          location: const LatLng(0, 0),
                          timestamp: now,
                        );
                        
                        // Create a test geofence using factory constructor
                        final testGeofence = Geofence.circle(
                          id: 'test',
                          userId: 'test',
                          name: 'Test Geofence',
                          center: const LatLng(0, 0),
                          radius: 100,
                        );
                        
                        // Show test notification
                        await notificationService.showGeofenceEvent(
                          testEvent,
                          testGeofence,
                          deviceName: 'Test Device',
                        );
                        
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Test notification sent!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to send: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.notifications),
                    label: const Text('Send Test Notification'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Troubleshooting Tips
          _buildSection(
            'Troubleshooting Tips',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTipCard(
                  '1. Check Geofence Triggers',
                  'Make sure "On Enter" or "On Exit" is enabled for your geofence',
                ),
                const SizedBox(height: 8),
                _buildTipCard(
                  '2. Verify Permissions',
                  'Location: "Allow all the time"\nNotifications: Enabled',
                ),
                const SizedBox(height: 8),
                _buildTipCard(
                  '3. Test with Movement',
                  'Create a 500m geofence, move 1km away, then return',
                ),
                const SizedBox(height: 8),
                _buildTipCard(
                  '4. Check Console Logs',
                  'Look for: 🔵 ENTER or 🔴 EXIT messages',
                ),
                const SizedBox(height: 8),
                _buildTipCard(
                  '5. Wait for Deduplication',
                  'Notifications are deduplicated for 30 seconds',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildSuccessCard(String title, String message) {
    return Card(
      color: Colors.green.shade50,
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: Colors.green, size: 32),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(message),
      ),
    );
  }

  Widget _buildWarningCard(String title, String message) {
    return Card(
      color: Colors.orange.shade50,
      child: ListTile(
        leading: const Icon(Icons.warning, color: Colors.orange, size: 32),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(message),
      ),
    );
  }

  Widget _buildErrorCard(String title, String message) {
    return Card(
      color: Colors.red.shade50,
      child: ListTile(
        leading: const Icon(Icons.error, color: Colors.red, size: 32),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(message),
      ),
    );
  }

  Widget _buildTipCard(String title, String message) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.lightbulb_outline, color: Colors.blue),
        title: Text(title),
        subtitle: Text(message),
        dense: true,
      ),
    );
  }
}
