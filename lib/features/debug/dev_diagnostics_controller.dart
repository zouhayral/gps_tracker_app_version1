import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runtime toggle for the Dev Diagnostics overlay (debug-only)
// Default disabled; can be re-enabled via manual gating if needed
final showDiagnosticsProvider = StateProvider<bool>((_) => false);
