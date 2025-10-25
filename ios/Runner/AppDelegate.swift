import Flutter
import UIKit
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  var locationManager: CLLocationManager?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Initialize location manager for background monitoring
    locationManager = CLLocationManager()
    locationManager?.delegate = self
    locationManager?.allowsBackgroundLocationUpdates = true
    locationManager?.pausesLocationUpdatesAutomatically = false
    
    // Request always authorization for background monitoring
    locationManager?.requestAlwaysAuthorization()
    
    // Start monitoring significant location changes
    // This keeps the app alive for coarse location updates in background
    locationManager?.startMonitoringSignificantLocationChanges()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - CLLocationManagerDelegate

  /// Called when device enters a monitored region
  /// This fires even if app is terminated (iOS 13+)
  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    print("[iOS Geofence] ✅ Entered region: \(region.identifier)")
    
    // TODO: Send event to Flutter via MethodChannel
    // or trigger local notification
    
    // For now, log the event
    NSLog("Geofence entry detected: \(region.identifier)")
  }

  /// Called when device exits a monitored region
  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    print("[iOS Geofence] 🚪 Exited region: \(region.identifier)")
    
    // TODO: Send event to Flutter via MethodChannel
    // or trigger local notification
    
    NSLog("Geofence exit detected: \(region.identifier)")
  }

  /// Called when region monitoring fails
  func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
    print("[iOS Geofence] ❌ Monitoring failed for region: \(region?.identifier ?? "unknown")")
    print("[iOS Geofence] Error: \(error.localizedDescription)")
  }

  /// Called when location manager authorization changes
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    switch status {
    case .authorizedAlways:
      print("[iOS Geofence] ✅ Always authorization granted")
      locationManager?.startMonitoringSignificantLocationChanges()
    case .authorizedWhenInUse:
      print("[iOS Geofence] ⚠️ Only 'When In Use' authorization granted")
    case .denied, .restricted:
      print("[iOS Geofence] ❌ Location authorization denied or restricted")
    case .notDetermined:
      print("[iOS Geofence] ⏳ Location authorization not yet determined")
    @unknown default:
      print("[iOS Geofence] ⚠️ Unknown authorization status")
    }
  }
}
