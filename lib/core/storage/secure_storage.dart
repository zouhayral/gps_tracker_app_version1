// Conditional export for platform-specific secure storage
export 'secure_storage_mobile.dart'
    if (dart.library.html) 'secure_storage_web.dart';

// Factory to create the appropriate storage implementation
import 'package:my_app_gps/core/storage/secure_storage_stub.dart'
    if (dart.library.io) 'secure_storage_mobile.dart'
    if (dart.library.html) 'secure_storage_web.dart';
import 'package:my_app_gps/core/storage/secure_storage_interface.dart';

SecureStorageInterface createSecureStorage() {
  // This will resolve to the platform-specific implementation at compile time
  return getSecureStorage();
}
