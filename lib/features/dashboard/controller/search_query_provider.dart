import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the dashboard search query to filter the devices list.
final searchQueryProvider = StateProvider<String>((ref) => '');
