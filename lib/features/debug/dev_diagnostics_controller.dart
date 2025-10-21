import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runtime toggle for the Dev Diagnostics overlay (debug-only)
final showDiagnosticsProvider = StateProvider<bool>((_) => true);
