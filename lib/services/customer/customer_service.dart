/// Customer service barrel export
/// 
/// Import this file to access all customer-related providers and models.
/// 
/// Example usage:
/// ```dart
/// import 'package:my_app_gps/services/customer/customer_service.dart';
/// 
/// // Login
/// final manager = ref.read(customerManagerProvider);
/// await manager.loginCustomer(
///   email: 'user@example.com',
///   password: 'password',
/// );
/// 
/// // Watch device positions
/// ref.watch(customerDevicePositionsProvider).when(
///   data: (positions) {
///     // Use positions map
///   },
///   loading: () => CircularProgressIndicator(),
///   error: (error, stack) => Text('Error: $error'),
/// );
/// ```
library;

export 'customer_credentials.dart';
export 'customer_device_positions.dart';
export 'customer_manager.dart';
export 'customer_session.dart';
export 'customer_websocket.dart';
