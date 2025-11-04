import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'GPS Tracker'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @reportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports & Statistics'**
  String get reportsTitle;

  /// No description provided for @reportsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View trips, speeds, and distances'**
  String get reportsSubtitle;

  /// No description provided for @period.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get period;

  /// No description provided for @device.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get device;

  /// No description provided for @distance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get distance;

  /// No description provided for @avgSpeed.
  ///
  /// In en, this message translates to:
  /// **'Avg. Speed'**
  String get avgSpeed;

  /// No description provided for @maxSpeed.
  ///
  /// In en, this message translates to:
  /// **'Max Speed'**
  String get maxSpeed;

  /// No description provided for @trips.
  ///
  /// In en, this message translates to:
  /// **'Trips'**
  String get trips;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select app language'**
  String get languageSubtitle;

  /// No description provided for @noData.
  ///
  /// In en, this message translates to:
  /// **'No data available'**
  String get noData;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @exportShareReport.
  ///
  /// In en, this message translates to:
  /// **'Export & Share Report'**
  String get exportShareReport;

  /// No description provided for @selectDevice.
  ///
  /// In en, this message translates to:
  /// **'Select a device'**
  String get selectDevice;

  /// No description provided for @noDevicesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No devices available'**
  String get noDevicesAvailable;

  /// No description provided for @pleaseSelectDevice.
  ///
  /// In en, this message translates to:
  /// **'Please select a device'**
  String get pleaseSelectDevice;

  /// No description provided for @noDeviceSelected.
  ///
  /// In en, this message translates to:
  /// **'No device is currently selected'**
  String get noDeviceSelected;

  /// No description provided for @loadingStatistics.
  ///
  /// In en, this message translates to:
  /// **'Loading statistics...'**
  String get loadingStatistics;

  /// No description provided for @loadingError.
  ///
  /// In en, this message translates to:
  /// **'Loading error'**
  String get loadingError;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @noTripsRecorded.
  ///
  /// In en, this message translates to:
  /// **'No trips recorded for this period'**
  String get noTripsRecorded;

  /// No description provided for @day.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get day;

  /// No description provided for @week.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get week;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get month;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @editPeriod.
  ///
  /// In en, this message translates to:
  /// **'Edit period'**
  String get editPeriod;

  /// No description provided for @generatingPdf.
  ///
  /// In en, this message translates to:
  /// **'Generating PDF...'**
  String get generatingPdf;

  /// No description provided for @reportSharedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Report shared successfully'**
  String get reportSharedSuccessfully;

  /// No description provided for @errorSharingReport.
  ///
  /// In en, this message translates to:
  /// **'Error sharing report'**
  String get errorSharingReport;

  /// No description provided for @noDataToExport.
  ///
  /// In en, this message translates to:
  /// **'No data to export'**
  String get noDataToExport;

  /// No description provided for @fuelUsed.
  ///
  /// In en, this message translates to:
  /// **'Fuel Used'**
  String get fuelUsed;

  /// No description provided for @speedEvolution.
  ///
  /// In en, this message translates to:
  /// **'Speed Evolution'**
  String get speedEvolution;

  /// No description provided for @tripDistribution.
  ///
  /// In en, this message translates to:
  /// **'Trip Distribution'**
  String get tripDistribution;

  /// No description provided for @periodSummary.
  ///
  /// In en, this message translates to:
  /// **'Period Summary'**
  String get periodSummary;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @end.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get end;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @notSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get notSignedIn;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @notificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off to stop receiving live alerts. You can still view them in the Alerts tab.'**
  String get notificationsSubtitle;

  /// No description provided for @analyticsReports.
  ///
  /// In en, this message translates to:
  /// **'Analytics & Reports'**
  String get analyticsReports;

  /// No description provided for @geofences.
  ///
  /// In en, this message translates to:
  /// **'Geofences'**
  String get geofences;

  /// No description provided for @manageGeofences.
  ///
  /// In en, this message translates to:
  /// **'Manage Geofences'**
  String get manageGeofences;

  /// No description provided for @manageGeofencesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create, edit, or configure geofence settings'**
  String get manageGeofencesSubtitle;

  /// No description provided for @languageDeveloperTools.
  ///
  /// In en, this message translates to:
  /// **'Language & Developer Tools'**
  String get languageDeveloperTools;

  /// No description provided for @currentLanguage.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get currentLanguage;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @localeTest.
  ///
  /// In en, this message translates to:
  /// **'Locale Test'**
  String get localeTest;

  /// No description provided for @localeTestSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Verify localization configuration'**
  String get localeTestSubtitle;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @loggedOut.
  ///
  /// In en, this message translates to:
  /// **'Logged out'**
  String get loggedOut;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @speed.
  ///
  /// In en, this message translates to:
  /// **'Speed (km/h)'**
  String get speed;

  /// No description provided for @numberOfTrips.
  ///
  /// In en, this message translates to:
  /// **'Number of trips'**
  String get numberOfTrips;

  /// No description provided for @tripCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No trips} =1{1 trip} other{{count} trips}}'**
  String tripCount(int count);

  /// No description provided for @chartsNotIncluded.
  ///
  /// In en, this message translates to:
  /// **'Charts not included'**
  String get chartsNotIncluded;

  /// No description provided for @generatedOn.
  ///
  /// In en, this message translates to:
  /// **'Generated on'**
  String get generatedOn;

  /// No description provided for @mainStatistics.
  ///
  /// In en, this message translates to:
  /// **'Main Statistics'**
  String get mainStatistics;

  /// No description provided for @metric.
  ///
  /// In en, this message translates to:
  /// **'Metric'**
  String get metric;

  /// No description provided for @value.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get value;

  /// No description provided for @periodDetails.
  ///
  /// In en, this message translates to:
  /// **'Period Details'**
  String get periodDetails;

  /// No description provided for @mapTitle.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get mapTitle;

  /// No description provided for @tripsTitle.
  ///
  /// In en, this message translates to:
  /// **'Trips'**
  String get tripsTitle;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get notificationsTitle;

  /// No description provided for @allDevices.
  ///
  /// In en, this message translates to:
  /// **'All devices'**
  String get allDevices;

  /// No description provided for @noUpdateYet.
  ///
  /// In en, this message translates to:
  /// **'No update yet'**
  String get noUpdateYet;

  /// No description provided for @updated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get updated;

  /// No description provided for @refreshData.
  ///
  /// In en, this message translates to:
  /// **'Refresh data'**
  String get refreshData;

  /// No description provided for @dataRefreshedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Data refreshed successfully'**
  String get dataRefreshedSuccessfully;

  /// No description provided for @refreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Refresh failed'**
  String get refreshFailed;

  /// No description provided for @mapLayer.
  ///
  /// In en, this message translates to:
  /// **'Map layer'**
  String get mapLayer;

  /// No description provided for @openInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Maps'**
  String get openInMaps;

  /// No description provided for @noValidCoordinates.
  ///
  /// In en, this message translates to:
  /// **'No valid coordinates available for this device'**
  String get noValidCoordinates;

  /// No description provided for @failedToOpenMaps.
  ///
  /// In en, this message translates to:
  /// **'Failed to open maps'**
  String get failedToOpenMaps;

  /// No description provided for @failedToLoadDevices.
  ///
  /// In en, this message translates to:
  /// **'Failed to load devices for map'**
  String get failedToLoadDevices;

  /// No description provided for @loadingMapTiles.
  ///
  /// In en, this message translates to:
  /// **'Loading map tiles...'**
  String get loadingMapTiles;

  /// No description provided for @loadingFleetData.
  ///
  /// In en, this message translates to:
  /// **'Loading fleet data...'**
  String get loadingFleetData;

  /// No description provided for @failedToLoadFleetData.
  ///
  /// In en, this message translates to:
  /// **'Failed to load fleet data'**
  String get failedToLoadFleetData;

  /// No description provided for @liveTracking.
  ///
  /// In en, this message translates to:
  /// **'Live Tracking'**
  String get liveTracking;

  /// No description provided for @centerMap.
  ///
  /// In en, this message translates to:
  /// **'Center Map'**
  String get centerMap;

  /// No description provided for @deviceOffline.
  ///
  /// In en, this message translates to:
  /// **'Device Offline'**
  String get deviceOffline;

  /// No description provided for @noDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No Devices Found'**
  String get noDevicesFound;

  /// No description provided for @engineAndMovement.
  ///
  /// In en, this message translates to:
  /// **'Engine & Movement'**
  String get engineAndMovement;

  /// No description provided for @engine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get engine;

  /// No description provided for @speedKmh.
  ///
  /// In en, this message translates to:
  /// **'Speed (km/h)'**
  String get speedKmh;

  /// No description provided for @lastLocation.
  ///
  /// In en, this message translates to:
  /// **'Last Location'**
  String get lastLocation;

  /// No description provided for @coordinates.
  ///
  /// In en, this message translates to:
  /// **'Coordinates'**
  String get coordinates;

  /// No description provided for @noLocationData.
  ///
  /// In en, this message translates to:
  /// **'No location data available'**
  String get noLocationData;

  /// No description provided for @devicesSelected.
  ///
  /// In en, this message translates to:
  /// **'devices selected'**
  String get devicesSelected;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'more'**
  String get more;

  /// No description provided for @filterYourTrips.
  ///
  /// In en, this message translates to:
  /// **'Filter Your Trips'**
  String get filterYourTrips;

  /// No description provided for @filterDescription.
  ///
  /// In en, this message translates to:
  /// **'Select devices and date range to view trips'**
  String get filterDescription;

  /// No description provided for @applyFilter.
  ///
  /// In en, this message translates to:
  /// **'Apply Filter'**
  String get applyFilter;

  /// No description provided for @quickAllDevices.
  ///
  /// In en, this message translates to:
  /// **'Quick: All Devices (24h)'**
  String get quickAllDevices;

  /// No description provided for @noTripsFound.
  ///
  /// In en, this message translates to:
  /// **'No trips found'**
  String get noTripsFound;

  /// No description provided for @filterTripsTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter Trips'**
  String get filterTripsTitle;

  /// No description provided for @dateRange.
  ///
  /// In en, this message translates to:
  /// **'Date Range'**
  String get dateRange;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @devicesAvailable.
  ///
  /// In en, this message translates to:
  /// **'{count} devices available'**
  String devicesAvailable(Object count);

  /// No description provided for @tripSummary.
  ///
  /// In en, this message translates to:
  /// **'Trip Summary'**
  String get tripSummary;

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetails;

  /// No description provided for @tripDetails.
  ///
  /// In en, this message translates to:
  /// **'Trip Details'**
  String get tripDetails;

  /// No description provided for @startTime.
  ///
  /// In en, this message translates to:
  /// **'Start Time'**
  String get startTime;

  /// No description provided for @endTime.
  ///
  /// In en, this message translates to:
  /// **'End Time'**
  String get endTime;

  /// No description provided for @follow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get follow;

  /// No description provided for @alertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alertsTitle;

  /// No description provided for @noAlerts.
  ///
  /// In en, this message translates to:
  /// **'No alerts yet'**
  String get noAlerts;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get markAllRead;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @refreshingAlerts.
  ///
  /// In en, this message translates to:
  /// **'Refreshing alerts...'**
  String get refreshingAlerts;

  /// No description provided for @failedToLoadAlerts.
  ///
  /// In en, this message translates to:
  /// **'Failed to load alerts'**
  String get failedToLoadAlerts;

  /// No description provided for @newEventsWillAppear.
  ///
  /// In en, this message translates to:
  /// **'New events will appear here'**
  String get newEventsWillAppear;

  /// No description provided for @markAll.
  ///
  /// In en, this message translates to:
  /// **'Mark all'**
  String get markAll;

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get deleteAll;

  /// No description provided for @deleteAllNotifications.
  ///
  /// In en, this message translates to:
  /// **'Delete all notifications?'**
  String get deleteAllNotifications;

  /// No description provided for @deleteAllNotificationsConfirm.
  ///
  /// In en, this message translates to:
  /// **'This will permanently remove all notifications from this device.'**
  String get deleteAllNotificationsConfirm;

  /// No description provided for @allNotificationsDeleted.
  ///
  /// In en, this message translates to:
  /// **'All notifications deleted'**
  String get allNotificationsDeleted;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @deviceId.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get deviceId;

  /// No description provided for @severity.
  ///
  /// In en, this message translates to:
  /// **'Severity'**
  String get severity;

  /// No description provided for @ignitionOn.
  ///
  /// In en, this message translates to:
  /// **'Ignition On'**
  String get ignitionOn;

  /// No description provided for @ignitionOff.
  ///
  /// In en, this message translates to:
  /// **'Ignition Off'**
  String get ignitionOff;

  /// No description provided for @deviceOnline.
  ///
  /// In en, this message translates to:
  /// **'Device Online'**
  String get deviceOnline;

  /// No description provided for @geofenceEnter.
  ///
  /// In en, this message translates to:
  /// **'Geofence Entered'**
  String get geofenceEnter;

  /// No description provided for @geofenceExit.
  ///
  /// In en, this message translates to:
  /// **'Geofence Exited'**
  String get geofenceExit;

  /// No description provided for @alarm.
  ///
  /// In en, this message translates to:
  /// **'Alarm'**
  String get alarm;

  /// No description provided for @overspeed.
  ///
  /// In en, this message translates to:
  /// **'Overspeed'**
  String get overspeed;

  /// No description provided for @maintenanceDue.
  ///
  /// In en, this message translates to:
  /// **'Maintenance Due'**
  String get maintenanceDue;

  /// No description provided for @deviceMoving.
  ///
  /// In en, this message translates to:
  /// **'Device Moving'**
  String get deviceMoving;

  /// No description provided for @deviceStopped.
  ///
  /// In en, this message translates to:
  /// **'Device Stopped'**
  String get deviceStopped;

  /// No description provided for @speedAlert.
  ///
  /// In en, this message translates to:
  /// **'Speed alert'**
  String get speedAlert;

  /// No description provided for @vehicleStopped.
  ///
  /// In en, this message translates to:
  /// **'Vehicle stopped'**
  String get vehicleStopped;

  /// No description provided for @vehicleMoving.
  ///
  /// In en, this message translates to:
  /// **'Vehicle moving'**
  String get vehicleMoving;

  /// No description provided for @vehicleStarted.
  ///
  /// In en, this message translates to:
  /// **'Vehicle started'**
  String get vehicleStarted;

  /// No description provided for @unknownDevice.
  ///
  /// In en, this message translates to:
  /// **'Unknown Device'**
  String get unknownDevice;

  /// No description provided for @alertDetails.
  ///
  /// In en, this message translates to:
  /// **'Alert Details'**
  String get alertDetails;

  /// No description provided for @triggeredAt.
  ///
  /// In en, this message translates to:
  /// **'Triggered at'**
  String get triggeredAt;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @basicInformation.
  ///
  /// In en, this message translates to:
  /// **'Basic Information'**
  String get basicInformation;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'optional'**
  String get optional;

  /// No description provided for @allDevicesLabel.
  ///
  /// In en, this message translates to:
  /// **'All Devices'**
  String get allDevicesLabel;

  /// No description provided for @createGeofence.
  ///
  /// In en, this message translates to:
  /// **'Create Geofence'**
  String get createGeofence;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @triggers.
  ///
  /// In en, this message translates to:
  /// **'Triggers'**
  String get triggers;

  /// No description provided for @polygon.
  ///
  /// In en, this message translates to:
  /// **'Polygon'**
  String get polygon;

  /// No description provided for @circle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get circle;

  /// No description provided for @drawBoundary.
  ///
  /// In en, this message translates to:
  /// **'Draw Boundary'**
  String get drawBoundary;

  /// No description provided for @useCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'Use Current Location'**
  String get useCurrentLocation;

  /// No description provided for @radius.
  ///
  /// In en, this message translates to:
  /// **'Radius'**
  String get radius;

  /// No description provided for @onEnter.
  ///
  /// In en, this message translates to:
  /// **'On Enter'**
  String get onEnter;

  /// No description provided for @onExit.
  ///
  /// In en, this message translates to:
  /// **'On Exit'**
  String get onExit;

  /// No description provided for @dwellTime.
  ///
  /// In en, this message translates to:
  /// **'Dwell Time'**
  String get dwellTime;

  /// No description provided for @monitoredDevices.
  ///
  /// In en, this message translates to:
  /// **'Monitored Devices'**
  String get monitoredDevices;

  /// No description provided for @sound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get sound;

  /// No description provided for @vibration.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get vibration;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @defaultPriority.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultPriority;

  /// No description provided for @both.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get both;

  /// No description provided for @push.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get push;

  /// No description provided for @local.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get local;

  /// No description provided for @triggerWhenDeviceEnters.
  ///
  /// In en, this message translates to:
  /// **'Trigger when device enters this area'**
  String get triggerWhenDeviceEnters;

  /// No description provided for @triggerWhenDeviceLeaves.
  ///
  /// In en, this message translates to:
  /// **'Trigger when device leaves this area'**
  String get triggerWhenDeviceLeaves;

  /// No description provided for @triggerWhenDeviceStays.
  ///
  /// In en, this message translates to:
  /// **'Trigger when device stays in area'**
  String get triggerWhenDeviceStays;

  /// No description provided for @monitorAllDevices.
  ///
  /// In en, this message translates to:
  /// **'Monitor all devices automatically'**
  String get monitorAllDevices;

  /// No description provided for @selectAtLeastOneDevice.
  ///
  /// In en, this message translates to:
  /// **'Select at least one device or enable \"All Devices\"'**
  String get selectAtLeastOneDevice;

  /// No description provided for @playNotificationSound.
  ///
  /// In en, this message translates to:
  /// **'Play notification sound'**
  String get playNotificationSound;

  /// No description provided for @vibrateOnNotification.
  ///
  /// In en, this message translates to:
  /// **'Vibrate on notification'**
  String get vibrateOnNotification;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get paused;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @entry.
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get entry;

  /// No description provided for @exit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exit;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'welcome back'**
  String get welcomeBack;

  /// No description provided for @enterYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Enter your account'**
  String get enterYourAccount;

  /// No description provided for @emailOrUsername.
  ///
  /// In en, this message translates to:
  /// **'Email or Username'**
  String get emailOrUsername;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'login'**
  String get login;

  /// No description provided for @enterEmailOrUsername.
  ///
  /// In en, this message translates to:
  /// **'Enter email or username'**
  String get enterEmailOrUsername;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get enterPassword;

  /// No description provided for @sessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session Expired'**
  String get sessionExpired;

  /// No description provided for @pleaseEnterPasswordToContinue.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password to continue'**
  String get pleaseEnterPasswordToContinue;

  /// No description provided for @validatingSession.
  ///
  /// In en, this message translates to:
  /// **'Validating your session...'**
  String get validatingSession;

  /// No description provided for @imageNotFound.
  ///
  /// In en, this message translates to:
  /// **'Image not found'**
  String get imageNotFound;

  /// No description provided for @geofenceSettings.
  ///
  /// In en, this message translates to:
  /// **'Geofence Settings'**
  String get geofenceSettings;

  /// No description provided for @aboutGeofenceSettings.
  ///
  /// In en, this message translates to:
  /// **'About Geofence Settings'**
  String get aboutGeofenceSettings;

  /// No description provided for @geofenceConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Geofence Configuration'**
  String get geofenceConfiguration;

  /// No description provided for @configureHowGeofencesWork.
  ///
  /// In en, this message translates to:
  /// **'Configure how geofences work, including monitoring, notifications, and performance optimization.'**
  String get configureHowGeofencesWork;

  /// No description provided for @enableGeofencing.
  ///
  /// In en, this message translates to:
  /// **'Enable Geofencing'**
  String get enableGeofencing;

  /// No description provided for @turnOnToReceiveAlerts.
  ///
  /// In en, this message translates to:
  /// **'Turn on to receive alerts when entering or exiting geofences'**
  String get turnOnToReceiveAlerts;

  /// No description provided for @signInToEnableGeofenceMonitoring.
  ///
  /// In en, this message translates to:
  /// **'Sign in to enable geofence monitoring'**
  String get signInToEnableGeofenceMonitoring;

  /// No description provided for @backgroundGeofenceMonitoringActive.
  ///
  /// In en, this message translates to:
  /// **'Background geofence monitoring and notifications are active'**
  String get backgroundGeofenceMonitoringActive;

  /// No description provided for @backgroundAccess.
  ///
  /// In en, this message translates to:
  /// **'Background Access'**
  String get backgroundAccess;

  /// No description provided for @backgroundGeofenceMonitoringEnabled.
  ///
  /// In en, this message translates to:
  /// **'Background geofence monitoring enabled'**
  String get backgroundGeofenceMonitoringEnabled;

  /// No description provided for @disabledAppMayMissEvents.
  ///
  /// In en, this message translates to:
  /// **'Disabled – app may miss events when closed'**
  String get disabledAppMayMissEvents;

  /// No description provided for @backgroundAccessGranted.
  ///
  /// In en, this message translates to:
  /// **'✅ Background access granted'**
  String get backgroundAccessGranted;

  /// No description provided for @foregroundOnlyModeActivated.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Foreground-only mode activated'**
  String get foregroundOnlyModeActivated;

  /// No description provided for @aboutForegroundMode.
  ///
  /// In en, this message translates to:
  /// **'About Foreground Mode'**
  String get aboutForegroundMode;

  /// No description provided for @inForegroundOnlyMode.
  ///
  /// In en, this message translates to:
  /// **'In foreground-only mode, geofence monitoring works only while the app is open. To receive alerts when the app is closed, enable background location access.'**
  String get inForegroundOnlyMode;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @adaptiveOptimization.
  ///
  /// In en, this message translates to:
  /// **'Adaptive Optimization'**
  String get adaptiveOptimization;

  /// No description provided for @disabledFixedEvaluationFrequency.
  ///
  /// In en, this message translates to:
  /// **'Disabled - Fixed evaluation frequency'**
  String get disabledFixedEvaluationFrequency;

  /// No description provided for @activeMode.
  ///
  /// In en, this message translates to:
  /// **'Active mode'**
  String get activeMode;

  /// No description provided for @idleMode.
  ///
  /// In en, this message translates to:
  /// **'Idle mode'**
  String get idleMode;

  /// No description provided for @batterySaver.
  ///
  /// In en, this message translates to:
  /// **'Battery saver'**
  String get batterySaver;

  /// No description provided for @interval.
  ///
  /// In en, this message translates to:
  /// **'interval'**
  String get interval;

  /// No description provided for @optimizationDisabled.
  ///
  /// In en, this message translates to:
  /// **'Optimization disabled'**
  String get optimizationDisabled;

  /// No description provided for @adaptiveOptimizationEnabled.
  ///
  /// In en, this message translates to:
  /// **'✅ Adaptive optimization enabled'**
  String get adaptiveOptimizationEnabled;

  /// No description provided for @adaptiveOptimizationDisabled.
  ///
  /// In en, this message translates to:
  /// **'⏸️ Adaptive optimization disabled'**
  String get adaptiveOptimizationDisabled;

  /// No description provided for @failedToStartOptimizer.
  ///
  /// In en, this message translates to:
  /// **'❌ Failed to start optimizer'**
  String get failedToStartOptimizer;

  /// No description provided for @optimizationStatistics.
  ///
  /// In en, this message translates to:
  /// **'Optimization Statistics'**
  String get optimizationStatistics;

  /// No description provided for @savings.
  ///
  /// In en, this message translates to:
  /// **'Savings'**
  String get savings;

  /// No description provided for @defaultNotificationType.
  ///
  /// In en, this message translates to:
  /// **'Default Notification Type'**
  String get defaultNotificationType;

  /// No description provided for @localOnly.
  ///
  /// In en, this message translates to:
  /// **'Local only'**
  String get localOnly;

  /// No description provided for @evaluationFrequency.
  ///
  /// In en, this message translates to:
  /// **'Evaluation Frequency'**
  String get evaluationFrequency;

  /// No description provided for @balancedRecommended.
  ///
  /// In en, this message translates to:
  /// **'Balanced (recommended)'**
  String get balancedRecommended;

  /// No description provided for @resetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to Defaults'**
  String get resetToDefaults;

  /// No description provided for @thisWillResetAllGeofenceSettings.
  ///
  /// In en, this message translates to:
  /// **'This will reset all geofence settings to their default values. Are you sure you want to continue?'**
  String get thisWillResetAllGeofenceSettings;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @settingsResetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'✅ Settings reset to defaults'**
  String get settingsResetToDefaults;

  /// No description provided for @geofenceMonitoringStarted.
  ///
  /// In en, this message translates to:
  /// **'✅ Geofence monitoring started'**
  String get geofenceMonitoringStarted;

  /// No description provided for @geofenceMonitoringStopped.
  ///
  /// In en, this message translates to:
  /// **'⏸️ Geofence monitoring stopped'**
  String get geofenceMonitoringStopped;

  /// No description provided for @failedToStartMonitoring.
  ///
  /// In en, this message translates to:
  /// **'❌ Failed to start monitoring'**
  String get failedToStartMonitoring;

  /// No description provided for @failedToStopMonitoring.
  ///
  /// In en, this message translates to:
  /// **'❌ Failed to stop monitoring'**
  String get failedToStopMonitoring;

  /// No description provided for @selectNotificationType.
  ///
  /// In en, this message translates to:
  /// **'Select Notification Type'**
  String get selectNotificationType;

  /// No description provided for @showNotificationsOnlyOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Show notifications only on this device'**
  String get showNotificationsOnlyOnThisDevice;

  /// No description provided for @pushOnly.
  ///
  /// In en, this message translates to:
  /// **'Push only'**
  String get pushOnly;

  /// No description provided for @sendPushNotificationsViaServer.
  ///
  /// In en, this message translates to:
  /// **'Send push notifications via server (requires network)'**
  String get sendPushNotificationsViaServer;

  /// No description provided for @bothLocalPush.
  ///
  /// In en, this message translates to:
  /// **'Both (Local + Push)'**
  String get bothLocalPush;

  /// No description provided for @sendBothLocalAndPushNotifications.
  ///
  /// In en, this message translates to:
  /// **'Send both local and push notifications'**
  String get sendBothLocalAndPushNotifications;

  /// No description provided for @silent.
  ///
  /// In en, this message translates to:
  /// **'Silent'**
  String get silent;

  /// No description provided for @noNotificationsEventsStillLogged.
  ///
  /// In en, this message translates to:
  /// **'No notifications (events still logged)'**
  String get noNotificationsEventsStillLogged;

  /// No description provided for @notificationTypeSetTo.
  ///
  /// In en, this message translates to:
  /// **'Notification type set to'**
  String get notificationTypeSetTo;

  /// No description provided for @selectEvaluationFrequency.
  ///
  /// In en, this message translates to:
  /// **'Select Evaluation Frequency'**
  String get selectEvaluationFrequency;

  /// No description provided for @fastRealTime.
  ///
  /// In en, this message translates to:
  /// **'Fast (Real-time)'**
  String get fastRealTime;

  /// No description provided for @checkEvery510sHighBatteryUsage.
  ///
  /// In en, this message translates to:
  /// **'Check every 5-10s (high battery usage)'**
  String get checkEvery510sHighBatteryUsage;

  /// No description provided for @checkEvery30sModerateBatteryUsage.
  ///
  /// In en, this message translates to:
  /// **'Check every 30s (moderate battery usage)'**
  String get checkEvery30sModerateBatteryUsage;

  /// No description provided for @batterySaverMode.
  ///
  /// In en, this message translates to:
  /// **'Battery Saver'**
  String get batterySaverMode;

  /// No description provided for @checkEvery60120sLowBatteryUsage.
  ///
  /// In en, this message translates to:
  /// **'Check every 60-120s (low battery usage)'**
  String get checkEvery60120sLowBatteryUsage;

  /// No description provided for @evaluationFrequencySetTo.
  ///
  /// In en, this message translates to:
  /// **'Evaluation frequency set to'**
  String get evaluationFrequencySetTo;

  /// No description provided for @controlsTheMainGeofenceMonitoringService.
  ///
  /// In en, this message translates to:
  /// **'Controls the main geofence monitoring service. When disabled, no geofence events will be detected.'**
  String get controlsTheMainGeofenceMonitoringService;

  /// No description provided for @allowsTheAppToDetectGeofenceEvents.
  ///
  /// In en, this message translates to:
  /// **'Allows the app to detect geofence events even when closed. Without this permission, monitoring only works while app is open.'**
  String get allowsTheAppToDetectGeofenceEvents;

  /// No description provided for @automaticallyAdjustsGeofenceCheckFrequency.
  ///
  /// In en, this message translates to:
  /// **'Automatically adjusts geofence check frequency based on battery level and device motion to save power.'**
  String get automaticallyAdjustsGeofenceCheckFrequency;

  /// No description provided for @chooseHowYouWantToBeNotified.
  ///
  /// In en, this message translates to:
  /// **'Choose how you want to be notified about geofence events. Local notifications work offline, push requires network.'**
  String get chooseHowYouWantToBeNotified;

  /// No description provided for @howOftenTheAppChecks.
  ///
  /// In en, this message translates to:
  /// **'How often the app checks if devices are inside geofences. Higher frequency = more battery usage but faster detection.'**
  String get howOftenTheAppChecks;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
