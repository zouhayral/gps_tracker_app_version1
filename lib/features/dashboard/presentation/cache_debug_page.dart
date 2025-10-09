import 'package:flutter/material.dart';
import '../../../core/network/forced_cache_interceptor.dart';

class CacheDebugPage extends StatefulWidget {
  const CacheDebugPage({super.key});

  @override
  State<CacheDebugPage> createState() => _CacheDebugPageState();
}

class _CacheDebugPageState extends State<CacheDebugPage> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _items = ForcedLocalCacheInterceptor.snapshot();
    });
  }

  void _clearAll() {
    ForcedLocalCacheInterceptor.clear();
    _refresh();
  }

  void _clearDevices() {
    ForcedLocalCacheInterceptor.clear(pathStartsWith: '/api/devices');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cache Debug'),
        actions: [
          IconButton(
            tooltip: 'Clear /api/devices',
            icon: const Icon(Icons.phonelink_erase),
            onPressed: _clearDevices,
          ),
          IconButton(
            tooltip: 'Clear All',
            icon: const Icon(Icons.delete_forever),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView.separated(
          itemCount: _items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final it = _items[index];
            final url = it['url'] as String? ?? '';
            final path = it['path'] as String? ?? '';
            final ageSec = it['ageSec'] as int? ?? 0;
            final size = it['size'] as int? ?? 0;
            return ListTile(
              title: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('age: ${ageSec}s'),
                  Text('size: ${size}B'),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
    );
  }
}
