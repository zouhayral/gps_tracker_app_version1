import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/dashboard/controller/search_provider.dart';
import 'package:my_app_gps/features/dashboard/controller/search_query_provider.dart' as legacy;

/// Simple device list view demonstrating the debounced search provider.
///
/// Notes:
/// - Uses a TextField bound to a query StateProvider (reuses legacy.searchQueryProvider).
/// - Watches [debouncedDeviceSearchProvider] to render filtered results.
/// - The provider internally debounces 250ms and offloads to an isolate for large lists.
class DeviceListView extends ConsumerWidget {
  const DeviceListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(legacy.searchQueryProvider);
    final resultsAsync = ref.watch(debouncedDeviceSearchProvider(query));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search devices',
            ),
            onChanged: (text) {
              // Update query immediately; results are debounced inside provider
              ref.read(legacy.searchQueryProvider.notifier).state = text;
            },
          ),
        ),
        Expanded(
          child: resultsAsync.when(
            data: (devices) {
              if (devices.isEmpty) {
                return const Center(child: Text('No devices found'));
              }
              return ListView.separated(
                itemCount: devices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final d = devices[i];
                  final name = (d['name'] as String?) ?? 'Unnamed';
                  final id = d['id'];
                  return ListTile(
                    title: Text(name),
                    subtitle: id is int ? Text('ID: $id') : null,
                    onTap: () {
                      // Example: You can navigate to device details here.
                    },
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }
}
