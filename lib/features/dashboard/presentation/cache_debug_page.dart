import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:my_app_gps/core/network/forced_cache_interceptor.dart';
import 'package:my_app_gps/core/network/http_cache_interceptor.dart';

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
    assert(
      debugCheckHasDirectionality(context),
      'CacheDebugPage requires Directionality above in the tree',
    );
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
                children: [Text('age: ${ageSec}s'), Text('size: ${size}B')],
              ),
            );
          },
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'clearTiles',
            onPressed: () async {
              // Clear flutter_map_tile_caching store and recreate it
              await const FMTCStore('main').manage.delete();
              await const FMTCStore('main').manage.create();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🧹 Map tile cache cleared.')),
                );
              }
              if (kDebugMode) {
                // ignore: avoid_print
                print('[CACHE][CLEAR] map tiles store=main');
              }
            },
            icon: const Icon(Icons.layers_clear),
            label: const Text('Clear Map Tile Cache'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'clearApi',
            onPressed: () async {
              ForcedLocalCacheInterceptor.clear();
              HttpCacheInterceptor.clear();
              _refresh();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🔁 API caches cleared.')),
                );
              }
              if (kDebugMode) {
                // ignore: avoid_print
                print('[CACHE][CLEAR] api forced+http caches');
              }
            },
            icon: const Icon(Icons.cached),
            label: const Text('Clear API Cache'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'refreshList',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh List'),
          ),
        ],
      ),
    );
  }
}
