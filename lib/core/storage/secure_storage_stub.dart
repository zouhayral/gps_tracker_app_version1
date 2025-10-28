import 'package:my_app_gps/core/storage/secure_storage_interface.dart';
import 'package:my_app_gps/core/storage/secure_storage_web.dart';

SecureStorageInterface getSecureStorage() => SecureStorageWeb();
