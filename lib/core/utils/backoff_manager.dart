import 'dart:math';

/// Exponential backoff manager for WebSocket reconnection.
/// 
/// Implements exponential backoff with configurable limits:
/// - Starts with initial delay (default: 1s)
/// - Doubles delay on each failure: 1s → 2s → 4s → 8s → 16s → 32s → 60s
/// - Caps at maximum delay (default: 60s)
/// - Resets to initial delay on successful connection
/// 
/// **Benefits:**
/// - Reduces server load during outages (progressive retry intervals)
/// - Prevents battery drain from aggressive reconnection attempts
/// - Balances recovery speed with resource conservation
/// 
/// **Usage:**
/// ```dart
/// final backoff = BackoffManager();
/// 
/// Future<void> reconnect() async {
///   while (!connected) {
///     final delay = backoff.nextDelay();
///     print('Retrying in ${delay.inSeconds}s...');
///     await Future.delayed(delay);
///     
///     final success = await _connect();
///     if (success) {
///       backoff.reset(); // Reset for next outage
///       break;
///     }
///   }
/// }
/// ```
class BackoffManager {
  /// Creates a backoff manager with configurable parameters.
  /// 
  /// [initialDelay] - Starting delay for first retry (default: 1s)
  /// [maxDelay] - Maximum delay cap (default: 60s)
  /// [multiplier] - Growth factor per attempt (default: 2.0 = exponential)
  BackoffManager({
    Duration initialDelay = const Duration(seconds: 1),
    Duration maxDelay = const Duration(seconds: 60),
    double multiplier = 2.0,
  })  : _initialDelay = initialDelay,
        _maxDelay = maxDelay,
        _multiplier = multiplier;

  final Duration _initialDelay;
  final Duration _maxDelay;
  final double _multiplier;
  
  int _attempt = 0;

  /// Calculates the next retry delay using exponential backoff.
  /// 
  /// Formula: delay = min(initialDelay × multiplier^attempt, maxDelay)
  /// 
  /// Automatically increments the attempt counter. Call [reset] after
  /// successful connection to restart the sequence.
  Duration nextDelay() {
    // Calculate exponential delay: initialDelay * multiplier^attempt
    final exponentialSeconds = _initialDelay.inSeconds * 
        pow(_multiplier, _attempt).toInt();
    
    // Cap at maximum delay
    final cappedSeconds = min(exponentialSeconds, _maxDelay.inSeconds);
    
    _attempt++;
    
    return Duration(seconds: cappedSeconds);
  }

  /// Resets the backoff counter to 0.
  /// 
  /// Call this after a successful connection to restart the backoff
  /// sequence for the next outage.
  void reset() {
    _attempt = 0;
  }

  /// Gets the current attempt number (0-indexed).
  int get currentAttempt => _attempt;

  /// Returns backoff statistics for diagnostics.
  Map<String, dynamic> getStats() {
    return {
      'currentAttempt': _attempt,
      'initialDelaySeconds': _initialDelay.inSeconds,
      'maxDelaySeconds': _maxDelay.inSeconds,
      'multiplier': _multiplier,
      'nextDelaySeconds': _attempt == 0 
          ? _initialDelay.inSeconds 
          : min(
              _initialDelay.inSeconds * pow(_multiplier, _attempt).toInt(),
              _maxDelay.inSeconds,
            ),
    };
  }
}
