/// FMTC runtime configuration flags used during development/troubleshooting.
/// Keep all flags defaulted to "safe" values for production.
class FmtcConfig {
  /// When true, the 'main' FMTC store will be deleted and recreated on startup.
  /// Useful if tiles were cached with an incompatible HTTP client and cause issues.
  /// **Set to true for ONE run, then revert to false.**
  static const bool kClearFMTCOnStartup = true;
}
