import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_app_gps/core/logging/rebuild_logger.dart';
import 'package:my_app_gps/core/utils/timing.dart';
import 'package:my_app_gps/features/auth/controller/auth_notifier.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/dashboard/controller/search_query_provider.dart';
import 'package:my_app_gps/features/map/data/granular_providers.dart';
// Removed temporary rate probe import (Validation 0.3 complete)

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final _searchCtrl = TextEditingController();
  final _searchDebouncer = Debouncer(const Duration(milliseconds: 250));

  @override
  void dispose() {
    _searchDebouncer.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch only the AsyncValue state; deeper selects can be applied within itemBuilder if needed
    final devicesAsync = ref.watch(devicesNotifierProvider);
    final query = ref.watch(searchQueryProvider);
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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        child: devicesAsync.when(
          data: (devices) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? devices
                : devices
                    .where((d) =>
                        (d['name']?.toString().toLowerCase() ?? '').contains(q),)
                    .toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search devices',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => _searchDebouncer.run(() {
                      ref.read(searchQueryProvider.notifier).state = v;
                    }),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No devices'))
                      : ListView.separated(
                          key: const ValueKey('devices-list'),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final id = filtered[i]['id'] as int;
                            return ProviderScope(child: _DeviceTile(id: id));
                          },
                        ),
                ),
              ],
            );
          },
          loading: () => const Center(
            key: ValueKey('devices-loading'),
            child: CircularProgressIndicator(),
          ),
          error: (e, _) => Center(
            key: const ValueKey('devices-error'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Failed to load devices',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.toString(),
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () =>
                        ref.read(devicesNotifierProvider.notifier).load(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      // FloatingActionButton removed (was temporary diagnostic probe)
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  const _DeviceTile({required this.id});
  final int id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Optimized with .select() to limit rebuilds to just this device object
    // Rebuild log for profiling - schedule after frame to avoid side-effects
    try {
      ref.scheduleLogRebuild('DeviceTile($id)');
    } catch (_) {}
    final d = ref.watch(deviceByIdProvider(id));
    if (d == null) return const SizedBox.shrink();
    // debugPrint('[REBUILD] DeviceTile($id) rebuilt');
    final nameText = Text(d['name']?.toString() ?? 'Unnamed');
    final subtitleText =
        Text('ID: ${d['id']}  Status: ${d['status'] ?? 'unknown'}');
    return ListTile(
      title: nameText,
      subtitle: subtitleText,
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        // Navigate to map with this device preselected and centered
        context.go('/map?device=$id');
      },
    );
  }
}
