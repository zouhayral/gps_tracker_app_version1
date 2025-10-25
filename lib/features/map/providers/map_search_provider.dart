import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for map search query state
/// 
/// Isolates search query changes from MapPage state, preventing
/// unnecessary parent widget rebuilds when user types in search field.
/// 
/// Usage:
/// ```dart
/// // Read query
/// final query = ref.watch(mapSearchQueryProvider);
/// 
/// // Update query
/// ref.read(mapSearchQueryProvider.notifier).state = 'new query';
/// ```
final mapSearchQueryProvider = StateProvider<String>((ref) => '');

/// Provider for search editing state
/// 
/// Controls whether the search field is in active editing mode.
final mapSearchEditingProvider = StateProvider<bool>((ref) => false);

/// Provider for search suggestions visibility
/// 
/// Controls whether the suggestions dropdown should be shown.
final mapSearchSuggestionsVisibleProvider = StateProvider<bool>((ref) => false);
