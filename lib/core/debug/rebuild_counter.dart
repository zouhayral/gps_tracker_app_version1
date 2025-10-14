import 'package:flutter/foundation.dart';

class RebuildCounter {
  RebuildCounter._();
  static final ValueNotifier<int> count = ValueNotifier<int>(0);
  static void increment() {
    if (kDebugMode) {
      count.value += 1;
    }
  }
}
