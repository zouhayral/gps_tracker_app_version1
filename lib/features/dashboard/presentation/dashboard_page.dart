import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/controller/auth_notifier.dart';
import '../controller/devices_notifier.dart';
// Removed temporary rate probe import (Validation 0.3 complete)

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesNotifierProvider);
  return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.read(devicesNotifierProvider.notifier).load(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).logout();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: devicesAsync.when(
        data: (devices) => devices.isEmpty
            ? const Center(child: Text('No devices'))
            : ListView.separated(
                itemCount: devices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final d = devices[i];
                  return ListTile(
                    title: Text(d['name']?.toString() ?? 'Unnamed'),
                    subtitle: Text('ID: ${d['id']}  Status: ${d['status'] ?? 'unknown'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {},
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Failed to load devices', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(e.toString(), style: const TextStyle(color: Colors.red, fontSize: 12)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => ref.read(devicesNotifierProvider.notifier).load(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      // FloatingActionButton removed (was temporary diagnostic probe)
    );
  }
}
