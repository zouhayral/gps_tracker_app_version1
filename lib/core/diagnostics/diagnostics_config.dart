/// Centralized diagnostics configuration.
/// Set these flags to enable/disable verbose performance logging globally.
class DiagnosticsConfig {
  /// When true, performance-related debugPrint logs (FPS, jank, summaries)
  /// will be emitted in debug/profile builds. Default is false to avoid spam.
  static const bool enablePerfLogs = false;
}
