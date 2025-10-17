import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/diagnostics/frame_metrics_logger.dart';
import 'package:my_app_gps/core/diagnostics/mock_device_stream.dart';
import 'package:my_app_gps/core/diagnostics/rebuild_tracker.dart';
import 'package:my_app_gps/services/device_update_service.dart';

/// Performance validation test page
///
/// Tests the map optimizations under various load scenarios:
/// - Light (10 devices, 10s)
/// - Normal (20 devices, 5s)
/// - Heavy (50 devices, 5s)
/// - Extreme (100 devices, 3s)
/// - Burst (30 devices, 1s)
class PerformanceTestPage extends ConsumerStatefulWidget {
  const PerformanceTestPage({super.key});

  @override
  ConsumerState<PerformanceTestPage> createState() =>
      _PerformanceTestPageState();
}

class _PerformanceTestPageState extends ConsumerState<PerformanceTestPage> {
  MockDeviceStream? _mockStream;
  FrameMetricsSession? _metricsSession;
  bool _isTestRunning = false;
  String _currentTest = 'None';
  int _updateCount = 0;

  @override
  void initState() {
    super.initState();
    // Enable rebuild tracking
    RebuildTracker.instance.start();
  }

  @override
  void dispose() {
    _stopTest();
    RebuildTracker.instance.stop();
    super.dispose();
  }

  void _startTest(String testName, MockDeviceStream stream) {
    // Stop any existing test
    _stopTest();

    setState(() {
      _isTestRunning = true;
      _currentTest = testName;
      _updateCount = 0;
    });

    // Start frame metrics
    _metricsSession = FrameMetricsSession();

    // Start mock stream
    _mockStream = stream;
    _mockStream!.start();

    // Wire mock stream to device update service
    final updateService = ref.read(deviceUpdateServiceProvider);
    _mockStream!.positionStream.listen((positions) {
      updateService.addBatchUpdates(positions);
      setState(() {
        _updateCount = _mockStream!.updateCount;
      });
    });

    debugPrint('[PerformanceTest] ✅ Started test: $testName');
  }

  void _stopTest() {
    if (!_isTestRunning) return;

    _mockStream?.stop();
    _mockStream?.dispose();
    _mockStream = null;

    _metricsSession?.end();
    _metricsSession = null;

    RebuildTracker.instance.printSummary();

    setState(() {
      _isTestRunning = false;
      _currentTest = 'None';
    });

    debugPrint('[PerformanceTest] ⏹️  Stopped test');
  }

  void _printCurrentMetrics() {
    if (_metricsSession != null) {
      _metricsSession!.printSummary();
      RebuildTracker.instance.printSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    RebuildTracker.instance.trackRebuild('PerformanceTestPage');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Test'),
        actions: [
          if (_isTestRunning)
            IconButton(
              icon: const Icon(Icons.assessment),
              onPressed: _printCurrentMetrics,
              tooltip: 'Print Metrics',
            ),
          if (_isTestRunning)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopTest,
              tooltip: 'Stop Test',
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Status card
            Card(
              color:
                  _isTestRunning ? Colors.green.shade100 : Colors.grey.shade200,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Status',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    _StatusRow(
                      label: 'Status',
                      value: _isTestRunning ? '🟢 RUNNING' : '⚪ IDLE',
                    ),
                    _StatusRow(
                      label: 'Current Test',
                      value: _currentTest,
                    ),
                    _StatusRow(
                      label: 'Updates Received',
                      value: '$_updateCount',
                    ),
                    if (_isTestRunning) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _printCurrentMetrics,
                        icon: const Icon(Icons.assessment),
                        label: const Text('Print Metrics Now'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Test scenarios
            Text(
              'Test Scenarios',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Select a test scenario to validate performance under different loads:',
              style: TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 16),

            _TestCard(
              title: 'Light Load',
              description: '10 devices, 10s update interval',
              icon: Icons.battery_charging_full,
              color: Colors.green,
              onPressed: _isTestRunning
                  ? null
                  : () {
                      _startTest('Light Load', MockDeviceScenarios.light());
                    },
            ),

            _TestCard(
              title: 'Normal Load',
              description:
                  '20 devices, 5s update interval\n(Typical Traccar setup)',
              icon: Icons.devices,
              color: Colors.blue,
              onPressed: _isTestRunning
                  ? null
                  : () {
                      _startTest('Normal Load', MockDeviceScenarios.normal());
                    },
            ),

            _TestCard(
              title: 'Heavy Load',
              description: '50 devices, 5s update interval',
              icon: Icons.warning_amber,
              color: Colors.orange,
              onPressed: _isTestRunning
                  ? null
                  : () {
                      _startTest('Heavy Load', MockDeviceScenarios.heavy());
                    },
            ),

            _TestCard(
              title: 'Extreme Load',
              description: '100 devices, 3s update interval',
              icon: Icons.local_fire_department,
              color: Colors.red,
              onPressed: _isTestRunning
                  ? null
                  : () {
                      _startTest('Extreme Load', MockDeviceScenarios.extreme());
                    },
            ),

            _TestCard(
              title: 'Burst Test',
              description: '30 devices, 1s update interval\n(Stress test)',
              icon: Icons.bolt,
              color: Colors.purple,
              onPressed: _isTestRunning
                  ? null
                  : () {
                      _startTest('Burst Test', MockDeviceScenarios.burst());
                    },
            ),

            _TestCard(
              title: 'Static Rendering',
              description: '50 devices, no movement\n(Tests rendering only)',
              icon: Icons.stop_circle_outlined,
              color: Colors.grey,
              onPressed: _isTestRunning
                  ? null
                  : () {
                      _startTest(
                        'Static Rendering',
                        MockDeviceScenarios.staticDevices(),
                      );
                    },
            ),

            const SizedBox(height: 24),

            // Expected results
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '✅ Expected Results',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const _ExpectedResultRow(
                      label: 'Frame Time',
                      value: '< 100 ms (< 16.67 ms ideal)',
                    ),
                    const _ExpectedResultRow(
                      label: 'Jank Count',
                      value: '< 5% of frames',
                    ),
                    const _ExpectedResultRow(
                      label: 'FlutterMap Rebuilds',
                      value: '0 (should be static)',
                    ),
                    const _ExpectedResultRow(
                      label: 'Marker Layer Rebuilds',
                      value: 'Only when positions change',
                    ),
                    const _ExpectedResultRow(
                      label: 'FPS',
                      value: '> 55 (60 target)',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Instructions
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'Instructions',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('1. Select a test scenario above'),
                    const Text('2. Let it run for 30-60 seconds'),
                    const Text('3. Tap "Print Metrics" or check console'),
                    const Text('4. Compare results with expected values'),
                    const Text('5. Check for rebuild counts in console'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description),
        trailing: ElevatedButton(
          onPressed: onPressed,
          child: const Text('Start'),
        ),
        enabled: onPressed != null,
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

class _ExpectedResultRow extends StatelessWidget {
  const _ExpectedResultRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }
}
