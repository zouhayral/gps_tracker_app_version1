// Conditional shim: use ObjectBox-annotated model on mobile, plain class on web.
export 'trip_snapshot_mobile.dart' if (dart.library.html) 'trip_snapshot_web.dart';
