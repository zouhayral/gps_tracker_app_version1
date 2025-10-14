import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/features/map/view/flutter_map_adapter.dart';

import 'test_utils/test_config.dart';

void main() {
  setUpAll(() async {
    await setupTestEnvironment();
  });

  test('setupTestEnvironment applies toggles', () async {
    expect(FlutterMapAdapterState.kDisableTilesForTests, isTrue);
  });
}
