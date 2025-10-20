import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A diagnostic panel to show WebSocket statistics and help debug event flow
/// 
/// Usage: Add to NotificationsPage during debugging:
/// ```dart
/// if (kDebugMode) WebSocketDiagnosticPanel(),
/// ```
class WebSocketDiagnosticPanel extends ConsumerWidget {
  const WebSocketDiagnosticPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.all(8),
      color: Colors.amber.shade50,
      child: ExpansionTile(
        leading: const Icon(Icons.bug_report, color: Colors.orange),
        title: const Text(
          'WebSocket Diagnostics',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Debugging event flow'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔍 Looking for Events?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Events are sent by Traccar ONLY when they occur.\n'
                  'Try triggering an event:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                _buildTestSection(context),
                const Divider(height: 24),
                _buildLogsSection(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '✅ How to Test:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        _buildTestItem('1', 'Turn vehicle ignition ON/OFF'),
        _buildTestItem('2', 'Create geofence in Traccar'),
        _buildTestItem('3', 'Drive in/out of geofence'),
        _buildTestItem('4', 'Exceed speed limit'),
        _buildTestItem('5', 'Turn off device (wait 5 min)'),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => _openTraccarDocs(context),
          icon: const Icon(Icons.help_outline),
          label: const Text('Open Diagnostic Guide'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildTestItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.orange.shade300,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildLogsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📋 Check Console Logs:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLogLine('✅', '[SOCKET] 🔑 Message contains keys: ...'),
              _buildLogLine('✅', '[SOCKET] 🔔 EVENTS RECEIVED (X events)'),
              _buildLogLine('✅', '[NotificationsRepository] 📨 Received...'),
              _buildLogLine('✅', '[NotificationsRepository] ✅ Persisted...'),
              const SizedBox(height: 8),
              const Text(
                '⚠️ If you see "NO EVENTS KEY" → Server not sending events',
                style: TextStyle(
                  color: Colors.yellow,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '💡 Tip: Events must be configured in Traccar server.\n'
          'Check TRACCAR_EVENTS_DIAGNOSTIC.md for details.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildLogLine(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$emoji $text',
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  void _openTraccarDocs(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diagnostic Resources'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Documentation Files:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('📄 TRACCAR_EVENTS_DIAGNOSTIC.md\n   → Complete diagnostic guide'),
              SizedBox(height: 8),
              Text('📄 NOTIFICATION_SYSTEM_IMPLEMENTATION.md\n   → System architecture'),
              SizedBox(height: 16),
              Text(
                'Online Resources:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('🌐 traccar.org/documentation/'),
              Text('🌐 traccar.org/api-reference/'),
              Text('🌐 traccar.org/forums/'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
