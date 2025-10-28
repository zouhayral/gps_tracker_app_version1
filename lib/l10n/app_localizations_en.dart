// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'GPS Tracker';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get reportsTitle => 'Reports & Statistics';

  @override
  String get reportsSubtitle => 'View trips, speeds, and distances';

  @override
  String get period => 'Period';

  @override
  String get device => 'Device';

  @override
  String get distance => 'Distance';

  @override
  String get avgSpeed => 'Avg Speed';

  @override
  String get maxSpeed => 'Max Speed';

  @override
  String get trips => 'Trips';

  @override
  String get language => 'Language';

  @override
  String get languageSubtitle => 'Select app language';

  @override
  String get noData => 'No data available';

  @override
  String get refresh => 'Refresh';

  @override
  String get exportShareReport => 'Export & Share Report';

  @override
  String get selectDevice => 'Select a device';

  @override
  String get noDevicesAvailable => 'No devices available';

  @override
  String get pleaseSelectDevice => 'Please select a device';

  @override
  String get noDeviceSelected => 'No device is currently selected';

  @override
  String get loadingStatistics => 'Loading statistics...';

  @override
  String get loadingError => 'Loading error';

  @override
  String get retry => 'Retry';

  @override
  String get noTripsRecorded => 'No trips recorded for this period';

  @override
  String get day => 'Day';

  @override
  String get week => 'Week';

  @override
  String get month => 'Month';

  @override
  String get custom => 'Custom';

  @override
  String get editPeriod => 'Edit period';

  @override
  String get generatingPdf => 'Generating PDF...';

  @override
  String get reportSharedSuccessfully => 'Report shared successfully';

  @override
  String get errorSharingReport => 'Error sharing report';

  @override
  String get noDataToExport => 'No data to export';

  @override
  String get fuelUsed => 'Fuel Used';

  @override
  String get speedEvolution => 'Speed Evolution';

  @override
  String get tripDistribution => 'Trip Distribution';

  @override
  String get periodSummary => 'Period Summary';

  @override
  String get start => 'Start';

  @override
  String get end => 'End';

  @override
  String get duration => 'Duration';

  @override
  String get account => 'Account';

  @override
  String get notSignedIn => 'Not signed in';

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationsSubtitle =>
      'Turn off to stop receiving live alerts. You can still view them in the Alerts tab.';

  @override
  String get analyticsReports => 'Analytics & Reports';

  @override
  String get geofences => 'Geofences';

  @override
  String get manageGeofences => 'Manage Geofences';

  @override
  String get manageGeofencesSubtitle =>
      'Create, edit, or configure geofence settings';

  @override
  String get languageDeveloperTools => 'Language & Developer Tools';

  @override
  String get currentLanguage => 'Current';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get localeTest => 'Locale Test';

  @override
  String get localeTestSubtitle => 'Verify localization configuration';

  @override
  String get logout => 'Logout';

  @override
  String get loggedOut => 'Logged out';

  @override
  String get cancel => 'Cancel';

  @override
  String get time => 'Time';

  @override
  String get speed => 'Speed';

  @override
  String get numberOfTrips => 'Number of trips';

  @override
  String tripCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trips',
      one: '1 trip',
      zero: 'No trips',
    );
    return '$_temp0';
  }

  @override
  String get chartsNotIncluded => 'Charts not included';

  @override
  String get generatedOn => 'Generated on';

  @override
  String get mainStatistics => 'Main Statistics';

  @override
  String get metric => 'Metric';

  @override
  String get value => 'Value';

  @override
  String get periodDetails => 'Period Details';

  @override
  String get mapTitle => 'Map';

  @override
  String get tripsTitle => 'Trips';

  @override
  String get notificationsTitle => 'Alerts';

  @override
  String get allDevices => 'All Devices';

  @override
  String get noUpdateYet => 'No update yet';

  @override
  String get updated => 'Updated';

  @override
  String get refreshData => 'Refresh data';

  @override
  String get dataRefreshedSuccessfully => 'Data refreshed successfully';

  @override
  String get refreshFailed => 'Refresh failed';

  @override
  String get mapLayer => 'Map layer';

  @override
  String get openInMaps => 'Open in Maps';

  @override
  String get noValidCoordinates =>
      'No valid coordinates available for this device';

  @override
  String get failedToOpenMaps => 'Failed to open maps';

  @override
  String get failedToLoadDevices => 'Failed to load devices for map';

  @override
  String get loadingMapTiles => 'Loading map tiles...';

  @override
  String get loadingFleetData => 'Loading fleet data...';

  @override
  String get failedToLoadFleetData => 'Failed to load fleet data';

  @override
  String get liveTracking => 'Live Tracking';

  @override
  String get centerMap => 'Center Map';

  @override
  String get deviceOffline => 'Device Offline';

  @override
  String get noDevicesFound => 'No Devices Found';

  @override
  String get engineAndMovement => 'Engine & Movement';

  @override
  String get engine => 'Engine';

  @override
  String get lastLocation => 'Last Location';

  @override
  String get coordinates => 'Coordinates';

  @override
  String get noLocationData => 'No location data available';

  @override
  String get devicesSelected => 'devices selected';

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get unknown => 'Unknown';

  @override
  String get more => 'more';

  @override
  String get filterYourTrips => 'Filter Your Trips';

  @override
  String get filterDescription => 'Select devices and date range to view trips';

  @override
  String get applyFilter => 'Apply Filter';

  @override
  String get quickAllDevices => 'Quick: All Devices (24h)';

  @override
  String get noTripsFound => 'No trips found';

  @override
  String get filterTripsTitle => 'Filter Trips';

  @override
  String get dateRange => 'Date Range';

  @override
  String get devices => 'Devices';

  @override
  String devicesAvailable(Object count) {
    return '$count devices available';
  }

  @override
  String get tripSummary => 'Trip Summary';

  @override
  String get viewDetails => 'View Details';

  @override
  String get alertsTitle => 'Alerts';

  @override
  String get noAlerts => 'No alerts yet';

  @override
  String get markAllRead => 'Mark all as read';

  @override
  String get clearAll => 'Clear all';

  @override
  String get refreshingAlerts => 'Refreshing alerts...';

  @override
  String get failedToLoadAlerts => 'Failed to load alerts';

  @override
  String get newEventsWillAppear => 'New events will appear here';

  @override
  String get markAll => 'Mark all';

  @override
  String get deleteAll => 'Delete all';

  @override
  String get deleteAllNotifications => 'Delete all notifications?';

  @override
  String get deleteAllNotificationsConfirm =>
      'This will permanently remove all notifications from this device.';

  @override
  String get allNotificationsDeleted => 'All notifications deleted';

  @override
  String get delete => 'Delete';

  @override
  String get close => 'Close';

  @override
  String get message => 'Message';

  @override
  String get deviceId => 'Device ID';

  @override
  String get severity => 'Severity';

  @override
  String get ignitionOn => 'Ignition On';

  @override
  String get ignitionOff => 'Ignition Off';

  @override
  String get deviceOnline => 'Device Online';

  @override
  String get geofenceEnter => 'Geofence Entered';

  @override
  String get geofenceExit => 'Geofence Exited';

  @override
  String get alarm => 'Alarm';

  @override
  String get overspeed => 'Overspeed';

  @override
  String get maintenanceDue => 'Maintenance Due';

  @override
  String get deviceMoving => 'Device Moving';

  @override
  String get deviceStopped => 'Device Stopped';

  @override
  String get speedAlert => 'Speed alert';

  @override
  String get vehicleStopped => 'Vehicle stopped';

  @override
  String get vehicleMoving => 'Vehicle moving';

  @override
  String get vehicleStarted => 'Vehicle started';

  @override
  String get unknownDevice => 'Unknown Device';

  @override
  String get alertDetails => 'Alert Details';

  @override
  String get triggeredAt => 'Triggered at';

  @override
  String get type => 'Type';

  @override
  String get location => 'Location';

  @override
  String get basicInformation => 'Basic Information';

  @override
  String get name => 'Name';

  @override
  String get description => 'Description';

  @override
  String get optional => 'optional';

  @override
  String get allDevicesLabel => 'All Devices';

  @override
  String get createGeofence => 'Create Geofence';

  @override
  String get save => 'Save';

  @override
  String get triggers => 'Triggers';

  @override
  String get polygon => 'Polygon';

  @override
  String get circle => 'Circle';

  @override
  String get drawBoundary => 'Draw Boundary';

  @override
  String get useCurrentLocation => 'Use Current Location';

  @override
  String get radius => 'Radius';

  @override
  String get onEnter => 'On Enter';

  @override
  String get onExit => 'On Exit';

  @override
  String get dwellTime => 'Dwell Time';

  @override
  String get monitoredDevices => 'Monitored Devices';

  @override
  String get sound => 'Sound';

  @override
  String get vibration => 'Vibration';

  @override
  String get priority => 'Priority';

  @override
  String get defaultPriority => 'Default';

  @override
  String get both => 'Both';

  @override
  String get push => 'Push';

  @override
  String get local => 'Local';

  @override
  String get triggerWhenDeviceEnters => 'Trigger when device enters this area';

  @override
  String get triggerWhenDeviceLeaves => 'Trigger when device leaves this area';

  @override
  String get triggerWhenDeviceStays => 'Trigger when device stays in area';

  @override
  String get monitorAllDevices => 'Monitor all devices automatically';

  @override
  String get selectAtLeastOneDevice =>
      'Select at least one device or enable \"All Devices\"';

  @override
  String get playNotificationSound => 'Play notification sound';

  @override
  String get vibrateOnNotification => 'Vibrate on notification';

  @override
  String get paused => 'Paused';

  @override
  String get active => 'Active';

  @override
  String get total => 'Total';

  @override
  String get entry => 'Entry';

  @override
  String get exit => 'Exit';

  @override
  String get welcomeBack => 'welcome back';

  @override
  String get enterYourAccount => 'Enter your account';

  @override
  String get emailOrUsername => 'Email or Username';

  @override
  String get password => 'Password';

  @override
  String get login => 'login';

  @override
  String get enterEmailOrUsername => 'Enter email or username';

  @override
  String get enterPassword => 'Enter password';

  @override
  String get sessionExpired => 'Session Expired';

  @override
  String get pleaseEnterPasswordToContinue =>
      'Please enter your password to continue';

  @override
  String get validatingSession => 'Validating your session...';

  @override
  String get imageNotFound => 'Image not found';

  @override
  String get geofenceSettings => 'Geofence Settings';

  @override
  String get aboutGeofenceSettings => 'About Geofence Settings';

  @override
  String get geofenceConfiguration => 'Geofence Configuration';

  @override
  String get configureHowGeofencesWork =>
      'Configure how geofences work, including monitoring, notifications, and performance optimization.';

  @override
  String get enableGeofencing => 'Enable Geofencing';

  @override
  String get turnOnToReceiveAlerts =>
      'Turn on to receive alerts when entering or exiting geofences';

  @override
  String get signInToEnableGeofenceMonitoring =>
      'Sign in to enable geofence monitoring';

  @override
  String get backgroundGeofenceMonitoringActive =>
      'Background geofence monitoring and notifications are active';

  @override
  String get backgroundAccess => 'Background Access';

  @override
  String get backgroundGeofenceMonitoringEnabled =>
      'Background geofence monitoring enabled';

  @override
  String get disabledAppMayMissEvents =>
      'Disabled – app may miss events when closed';

  @override
  String get backgroundAccessGranted => '✅ Background access granted';

  @override
  String get foregroundOnlyModeActivated => '⚠️ Foreground-only mode activated';

  @override
  String get aboutForegroundMode => 'About Foreground Mode';

  @override
  String get inForegroundOnlyMode =>
      'In foreground-only mode, geofence monitoring works only while the app is open. To receive alerts when the app is closed, enable background location access.';

  @override
  String get gotIt => 'Got it';

  @override
  String get adaptiveOptimization => 'Adaptive Optimization';

  @override
  String get disabledFixedEvaluationFrequency =>
      'Disabled - Fixed evaluation frequency';

  @override
  String get activeMode => 'Active mode';

  @override
  String get idleMode => 'Idle mode';

  @override
  String get batterySaver => 'Battery saver';

  @override
  String get interval => 'interval';

  @override
  String get optimizationDisabled => 'Optimization disabled';

  @override
  String get adaptiveOptimizationEnabled => '✅ Adaptive optimization enabled';

  @override
  String get adaptiveOptimizationDisabled =>
      '⏸️ Adaptive optimization disabled';

  @override
  String get failedToStartOptimizer => '❌ Failed to start optimizer';

  @override
  String get optimizationStatistics => 'Optimization Statistics';

  @override
  String get savings => 'Savings';

  @override
  String get defaultNotificationType => 'Default Notification Type';

  @override
  String get localOnly => 'Local only';

  @override
  String get evaluationFrequency => 'Evaluation Frequency';

  @override
  String get balancedRecommended => 'Balanced (recommended)';

  @override
  String get resetToDefaults => 'Reset to Defaults';

  @override
  String get thisWillResetAllGeofenceSettings =>
      'This will reset all geofence settings to their default values. Are you sure you want to continue?';

  @override
  String get reset => 'Reset';

  @override
  String get settingsResetToDefaults => '✅ Settings reset to defaults';

  @override
  String get geofenceMonitoringStarted => '✅ Geofence monitoring started';

  @override
  String get geofenceMonitoringStopped => '⏸️ Geofence monitoring stopped';

  @override
  String get failedToStartMonitoring => '❌ Failed to start monitoring';

  @override
  String get failedToStopMonitoring => '❌ Failed to stop monitoring';

  @override
  String get selectNotificationType => 'Select Notification Type';

  @override
  String get showNotificationsOnlyOnThisDevice =>
      'Show notifications only on this device';

  @override
  String get pushOnly => 'Push only';

  @override
  String get sendPushNotificationsViaServer =>
      'Send push notifications via server (requires network)';

  @override
  String get bothLocalPush => 'Both (Local + Push)';

  @override
  String get sendBothLocalAndPushNotifications =>
      'Send both local and push notifications';

  @override
  String get silent => 'Silent';

  @override
  String get noNotificationsEventsStillLogged =>
      'No notifications (events still logged)';

  @override
  String get notificationTypeSetTo => 'Notification type set to';

  @override
  String get selectEvaluationFrequency => 'Select Evaluation Frequency';

  @override
  String get fastRealTime => 'Fast (Real-time)';

  @override
  String get checkEvery510sHighBatteryUsage =>
      'Check every 5-10s (high battery usage)';

  @override
  String get checkEvery30sModerateBatteryUsage =>
      'Check every 30s (moderate battery usage)';

  @override
  String get batterySaverMode => 'Battery Saver';

  @override
  String get checkEvery60120sLowBatteryUsage =>
      'Check every 60-120s (low battery usage)';

  @override
  String get evaluationFrequencySetTo => 'Evaluation frequency set to';

  @override
  String get controlsTheMainGeofenceMonitoringService =>
      'Controls the main geofence monitoring service. When disabled, no geofence events will be detected.';

  @override
  String get allowsTheAppToDetectGeofenceEvents =>
      'Allows the app to detect geofence events even when closed. Without this permission, monitoring only works while app is open.';

  @override
  String get automaticallyAdjustsGeofenceCheckFrequency =>
      'Automatically adjusts geofence check frequency based on battery level and device motion to save power.';

  @override
  String get chooseHowYouWantToBeNotified =>
      'Choose how you want to be notified about geofence events. Local notifications work offline, push requires network.';

  @override
  String get howOftenTheAppChecks =>
      'How often the app checks if devices are inside geofences. Higher frequency = more battery usage but faster detection.';
}
