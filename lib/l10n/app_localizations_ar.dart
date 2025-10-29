// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'تتبع GPS';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get reportsTitle => 'التقارير والإحصائيات';

  @override
  String get reportsSubtitle => 'عرض الرحلات والسرعات والمسافات';

  @override
  String get period => 'الفترة';

  @override
  String get device => 'الجهاز';

  @override
  String get distance => 'المسافة';

  @override
  String get avgSpeed => 'السرعة المتوسطة';

  @override
  String get maxSpeed => 'أقصى سرعة';

  @override
  String get trips => 'الرحلات';

  @override
  String get language => 'اللغة';

  @override
  String get languageSubtitle => 'اختر لغة التطبيق';

  @override
  String get noData => 'لا توجد بيانات متاحة';

  @override
  String get refresh => 'تحديث';

  @override
  String get exportShareReport => 'تصدير ومشاركة التقرير';

  @override
  String get selectDevice => 'اختر جهازًا';

  @override
  String get noDevicesAvailable => 'لا توجد أجهزة متاحة';

  @override
  String get pleaseSelectDevice => 'الرجاء اختيار جهاز';

  @override
  String get noDeviceSelected => 'لم يتم اختيار أي جهاز حاليًا';

  @override
  String get loadingStatistics => 'جارٍ تحميل الإحصائيات...';

  @override
  String get loadingError => 'خطأ في التحميل';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get noTripsRecorded => 'لم يتم تسجيل رحلات لهذه الفترة';

  @override
  String get day => 'يوم';

  @override
  String get week => 'أسبوع';

  @override
  String get month => 'شهر';

  @override
  String get custom => 'مخصص';

  @override
  String get editPeriod => 'تعديل الفترة';

  @override
  String get generatingPdf => 'جارٍ إنشاء ملف PDF...';

  @override
  String get reportSharedSuccessfully => 'تم مشاركة التقرير بنجاح';

  @override
  String get errorSharingReport => 'خطأ في مشاركة التقرير';

  @override
  String get noDataToExport => 'لا توجد بيانات للتصدير';

  @override
  String get fuelUsed => 'الوقود المستخدم';

  @override
  String get speedEvolution => 'تطور السرعة';

  @override
  String get tripDistribution => 'توزيع الرحلات';

  @override
  String get periodSummary => 'ملخص الفترة';

  @override
  String get start => 'البداية';

  @override
  String get end => 'النهاية';

  @override
  String get duration => 'المدة';

  @override
  String get account => 'الحساب';

  @override
  String get notSignedIn => 'غير مسجل الدخول';

  @override
  String get notifications => 'الإشعارات';

  @override
  String get notificationsSubtitle =>
      'قم بإيقاف التشغيل لإيقاف تلقي التنبيهات المباشرة. يمكنك عرضها في علامة التبويب التنبيهات.';

  @override
  String get analyticsReports => 'التحليلات والتقارير';

  @override
  String get geofences => 'السياجات الجغرافية';

  @override
  String get manageGeofences => 'إدارة السياجات الجغرافية';

  @override
  String get manageGeofencesSubtitle =>
      'إنشاء أو تعديل أو تكوين إعدادات السياج الجغرافي';

  @override
  String get languageDeveloperTools => 'اللغة وأدوات المطور';

  @override
  String get currentLanguage => 'الحالي';

  @override
  String get selectLanguage => 'اختر اللغة';

  @override
  String get localeTest => 'اختبار اللغة';

  @override
  String get localeTestSubtitle => 'التحقق من تكوين اللغة';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get loggedOut => 'تم تسجيل الخروج';

  @override
  String get cancel => 'إلغاء';

  @override
  String get time => 'الوقت';

  @override
  String get speed => 'السرعة (كم/ساعة)';

  @override
  String get numberOfTrips => 'عدد الرحلات';

  @override
  String tripCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count رحلات',
      one: 'رحلة واحدة',
      zero: 'لا توجد رحلات',
    );
    return '$_temp0';
  }

  @override
  String get chartsNotIncluded => 'الرسوم البيانية غير مشمولة';

  @override
  String get generatedOn => 'تم الإنشاء في';

  @override
  String get mainStatistics => 'الإحصائيات الرئيسية';

  @override
  String get metric => 'المقياس';

  @override
  String get value => 'القيمة';

  @override
  String get periodDetails => 'تفاصيل الفترة';

  @override
  String get mapTitle => 'الخريطة';

  @override
  String get tripsTitle => 'الرحلات';

  @override
  String get notificationsTitle => 'التنبيهات';

  @override
  String get allDevices => 'كل الأجهزة';

  @override
  String get noUpdateYet => 'لا يوجد تحديث بعد';

  @override
  String get updated => 'تم التحديث';

  @override
  String get refreshData => 'تحديث البيانات';

  @override
  String get dataRefreshedSuccessfully => 'تم تحديث البيانات بنجاح';

  @override
  String get refreshFailed => 'فشل التحديث';

  @override
  String get mapLayer => 'طبقة الخريطة';

  @override
  String get openInMaps => 'فتح في الخرائط';

  @override
  String get noValidCoordinates => 'لا توجد إحداثيات صالحة متاحة لهذا الجهاز';

  @override
  String get failedToOpenMaps => 'فشل فتح الخرائط';

  @override
  String get failedToLoadDevices => 'فشل تحميل الأجهزة للخريطة';

  @override
  String get loadingMapTiles => 'جاري تحميل بلاطات الخريطة...';

  @override
  String get loadingFleetData => 'جاري تحميل بيانات الأسطول...';

  @override
  String get failedToLoadFleetData => 'فشل تحميل بيانات الأسطول';

  @override
  String get liveTracking => 'تتبع مباشر';

  @override
  String get centerMap => 'توسيط الخريطة';

  @override
  String get deviceOffline => 'الجهاز غير متصل';

  @override
  String get noDevicesFound => 'لم يتم العثور على أجهزة';

  @override
  String get engineAndMovement => 'المحرك والحركة';

  @override
  String get engine => 'المحرك';

  @override
  String get speedKmh => 'Speed (km/h)';

  @override
  String get lastLocation => 'آخر موقع';

  @override
  String get coordinates => 'الإحداثيات';

  @override
  String get noLocationData => 'لا توجد بيانات موقع متاحة';

  @override
  String get devicesSelected => 'أجهزة محددة';

  @override
  String get online => 'متصل';

  @override
  String get offline => 'غير متصل';

  @override
  String get unknown => 'غير معروف';

  @override
  String get more => 'المزيد';

  @override
  String get filterYourTrips => 'تصفية رحلاتك';

  @override
  String get filterDescription => 'حدد الأجهزة ونطاق التاريخ لعرض الرحلات';

  @override
  String get applyFilter => 'تطبيق الفلتر';

  @override
  String get quickAllDevices => 'سريع: جميع الأجهزة (24 ساعة)';

  @override
  String get noTripsFound => 'لم يتم العثور على رحلات';

  @override
  String get filterTripsTitle => 'تصفية الرحلات';

  @override
  String get dateRange => 'نطاق التاريخ';

  @override
  String get devices => 'الأجهزة';

  @override
  String devicesAvailable(Object count) {
    return '$count أجهزة متاحة';
  }

  @override
  String get tripSummary => 'ملخص الرحلات';

  @override
  String get viewDetails => 'عرض التفاصيل';

  @override
  String get alertsTitle => 'التنبيهات';

  @override
  String get noAlerts => 'لا توجد تنبيهات بعد';

  @override
  String get markAllRead => 'تحديد الكل كمقروء';

  @override
  String get clearAll => 'مسح الكل';

  @override
  String get refreshingAlerts => 'جاري تحديث التنبيهات...';

  @override
  String get failedToLoadAlerts => 'فشل تحميل التنبيهات';

  @override
  String get newEventsWillAppear => 'ستظهر الأحداث الجديدة هنا';

  @override
  String get markAll => 'تحديد الكل';

  @override
  String get deleteAll => 'حذف الكل';

  @override
  String get deleteAllNotifications => 'حذف جميع الإشعارات؟';

  @override
  String get deleteAllNotificationsConfirm =>
      'سيؤدي هذا إلى حذف جميع الإشعارات من هذا الجهاز بشكل دائم.';

  @override
  String get allNotificationsDeleted => 'تم حذف جميع الإشعارات';

  @override
  String get delete => 'حذف';

  @override
  String get close => 'إغلاق';

  @override
  String get message => 'الرسالة';

  @override
  String get deviceId => 'معرف الجهاز';

  @override
  String get severity => 'الخطورة';

  @override
  String get ignitionOn => 'تم تشغيل الإشعال';

  @override
  String get ignitionOff => 'تم إيقاف الإشعال';

  @override
  String get deviceOnline => 'الجهاز متصل';

  @override
  String get geofenceEnter => 'دخول المنطقة الجغرافية';

  @override
  String get geofenceExit => 'خروج من المنطقة الجغرافية';

  @override
  String get alarm => 'إنذار';

  @override
  String get overspeed => 'تجاوز السرعة';

  @override
  String get maintenanceDue => 'صيانة مطلوبة';

  @override
  String get deviceMoving => 'الجهاز يتحرك';

  @override
  String get deviceStopped => 'الجهاز متوقف';

  @override
  String get speedAlert => 'تنبيه السرعة';

  @override
  String get vehicleStopped => 'تم إيقاف المركبة';

  @override
  String get vehicleMoving => 'المركبة تتحرك';

  @override
  String get vehicleStarted => 'تم تشغيل المركبة';

  @override
  String get unknownDevice => 'جهاز غير معروف';

  @override
  String get alertDetails => 'تفاصيل التنبيه';

  @override
  String get triggeredAt => 'تم التفعيل في';

  @override
  String get type => 'النوع';

  @override
  String get location => 'الموقع';

  @override
  String get basicInformation => 'المعلومات الأساسية';

  @override
  String get name => 'الاسم';

  @override
  String get description => 'الوصف';

  @override
  String get optional => 'اختياري';

  @override
  String get allDevicesLabel => 'جميع الأجهزة';

  @override
  String get createGeofence => 'إنشاء سياج جغرافي';

  @override
  String get save => 'حفظ';

  @override
  String get triggers => 'المشغلات';

  @override
  String get polygon => 'مضلع';

  @override
  String get circle => 'دائرة';

  @override
  String get drawBoundary => 'رسم الحدود';

  @override
  String get useCurrentLocation => 'استخدام الموقع الحالي';

  @override
  String get radius => 'نصف القطر';

  @override
  String get onEnter => 'عند الدخول';

  @override
  String get onExit => 'عند الخروج';

  @override
  String get dwellTime => 'وقت المكوث';

  @override
  String get monitoredDevices => 'الأجهزة المراقبة';

  @override
  String get sound => 'الصوت';

  @override
  String get vibration => 'الاهتزاز';

  @override
  String get priority => 'الأولوية';

  @override
  String get defaultPriority => 'افتراضي';

  @override
  String get both => 'كلاهما';

  @override
  String get push => 'دفع';

  @override
  String get local => 'محلي';

  @override
  String get triggerWhenDeviceEnters =>
      'التفعيل عند دخول الجهاز إلى هذه المنطقة';

  @override
  String get triggerWhenDeviceLeaves =>
      'التفعيل عند خروج الجهاز من هذه المنطقة';

  @override
  String get triggerWhenDeviceStays => 'التفعيل عند بقاء الجهاز في المنطقة';

  @override
  String get monitorAllDevices => 'مراقبة جميع الأجهزة تلقائياً';

  @override
  String get selectAtLeastOneDevice =>
      'اختر جهازاً واحداً على الأقل أو فعّل \"جميع الأجهزة\"';

  @override
  String get playNotificationSound => 'تشغيل صوت الإشعار';

  @override
  String get vibrateOnNotification => 'الاهتزاز عند الإشعار';

  @override
  String get paused => 'متوقف مؤقتاً';

  @override
  String get active => 'نشط';

  @override
  String get total => 'الإجمالي';

  @override
  String get entry => 'دخول';

  @override
  String get exit => 'خروج';

  @override
  String get welcomeBack => 'مرحباً بعودتك';

  @override
  String get enterYourAccount => 'أدخل حسابك';

  @override
  String get emailOrUsername => 'البريد الإلكتروني أو اسم المستخدم';

  @override
  String get password => 'كلمة المرور';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get enterEmailOrUsername => 'أدخل البريد الإلكتروني أو اسم المستخدم';

  @override
  String get enterPassword => 'أدخل كلمة المرور';

  @override
  String get sessionExpired => 'انتهت الجلسة';

  @override
  String get pleaseEnterPasswordToContinue =>
      'الرجاء إدخال كلمة المرور للمتابعة';

  @override
  String get validatingSession => 'التحقق من جلستك...';

  @override
  String get imageNotFound => 'الصورة غير موجودة';

  @override
  String get geofenceSettings => 'إعدادات السياج الجغرافي';

  @override
  String get aboutGeofenceSettings => 'حول إعدادات السياج الجغرافي';

  @override
  String get geofenceConfiguration => 'تكوين السياج الجغرافي';

  @override
  String get configureHowGeofencesWork =>
      'قم بتكوين كيفية عمل السياج الجغرافي، بما في ذلك المراقبة والإشعارات وتحسين الأداء.';

  @override
  String get enableGeofencing => 'تفعيل السياج الجغرافي';

  @override
  String get turnOnToReceiveAlerts =>
      'قم بالتشغيل لتلقي التنبيهات عند الدخول أو الخروج من السياج الجغرافي';

  @override
  String get signInToEnableGeofenceMonitoring =>
      'سجل الدخول لتفعيل مراقبة السياج الجغرافي';

  @override
  String get backgroundGeofenceMonitoringActive =>
      'مراقبة السياج الجغرافي والإشعارات في الخلفية نشطة';

  @override
  String get backgroundAccess => 'الوصول في الخلفية';

  @override
  String get backgroundGeofenceMonitoringEnabled =>
      'مراقبة السياج الجغرافي في الخلفية مفعّلة';

  @override
  String get disabledAppMayMissEvents =>
      'معطّل – قد يفوت التطبيق الأحداث عند إغلاقه';

  @override
  String get backgroundAccessGranted => '✅ تم منح الوصول في الخلفية';

  @override
  String get foregroundOnlyModeActivated => '⚠️ تم تفعيل وضع المقدمة فقط';

  @override
  String get aboutForegroundMode => 'حول وضع المقدمة';

  @override
  String get inForegroundOnlyMode =>
      'في وضع المقدمة فقط، تعمل مراقبة السياج الجغرافي فقط أثناء فتح التطبيق. لتلقي التنبيهات عند إغلاق التطبيق، قم بتفعيل الوصول إلى الموقع في الخلفية.';

  @override
  String get gotIt => 'فهمت';

  @override
  String get adaptiveOptimization => 'التحسين التكيفي';

  @override
  String get disabledFixedEvaluationFrequency => 'معطّل - تردد التقييم الثابت';

  @override
  String get activeMode => 'الوضع النشط';

  @override
  String get idleMode => 'وضع الخمول';

  @override
  String get batterySaver => 'موفر البطارية';

  @override
  String get interval => 'الفاصل الزمني';

  @override
  String get optimizationDisabled => 'التحسين معطّل';

  @override
  String get adaptiveOptimizationEnabled => '✅ تم تفعيل التحسين التكيفي';

  @override
  String get adaptiveOptimizationDisabled => '⏸️ تم تعطيل التحسين التكيفي';

  @override
  String get failedToStartOptimizer => '❌ فشل بدء المحسّن';

  @override
  String get optimizationStatistics => 'إحصائيات التحسين';

  @override
  String get savings => 'التوفير';

  @override
  String get defaultNotificationType => 'نوع الإشعار الافتراضي';

  @override
  String get localOnly => 'محلي فقط';

  @override
  String get evaluationFrequency => 'تردد التقييم';

  @override
  String get balancedRecommended => 'متوازن (موصى به)';

  @override
  String get resetToDefaults => 'إعادة تعيين إلى الافتراضيات';

  @override
  String get thisWillResetAllGeofenceSettings =>
      'سيؤدي هذا إلى إعادة تعيين جميع إعدادات السياج الجغرافي إلى قيمها الافتراضية. هل أنت متأكد أنك تريد المتابعة؟';

  @override
  String get reset => 'إعادة تعيين';

  @override
  String get settingsResetToDefaults =>
      '✅ تم إعادة تعيين الإعدادات إلى الافتراضيات';

  @override
  String get geofenceMonitoringStarted => '✅ بدأت مراقبة السياج الجغرافي';

  @override
  String get geofenceMonitoringStopped => '⏸️ توقفت مراقبة السياج الجغرافي';

  @override
  String get failedToStartMonitoring => '❌ فشل بدء المراقبة';

  @override
  String get failedToStopMonitoring => '❌ فشل إيقاف المراقبة';

  @override
  String get selectNotificationType => 'حدد نوع الإشعار';

  @override
  String get showNotificationsOnlyOnThisDevice =>
      'إظهار الإشعارات على هذا الجهاز فقط';

  @override
  String get pushOnly => 'دفع فقط';

  @override
  String get sendPushNotificationsViaServer =>
      'إرسال إشعارات الدفع عبر الخادم (يتطلب شبكة)';

  @override
  String get bothLocalPush => 'كلاهما (محلي + دفع)';

  @override
  String get sendBothLocalAndPushNotifications =>
      'إرسال الإشعارات المحلية والدفع';

  @override
  String get silent => 'صامت';

  @override
  String get noNotificationsEventsStillLogged =>
      'لا توجد إشعارات (لا تزال الأحداث مسجلة)';

  @override
  String get notificationTypeSetTo => 'تم تعيين نوع الإشعار إلى';

  @override
  String get selectEvaluationFrequency => 'حدد تردد التقييم';

  @override
  String get fastRealTime => 'سريع (وقت حقيقي)';

  @override
  String get checkEvery510sHighBatteryUsage =>
      'التحقق كل 5-10 ثانية (استهلاك عالٍ للبطارية)';

  @override
  String get checkEvery30sModerateBatteryUsage =>
      'التحقق كل 30 ثانية (استهلاك معتدل للبطارية)';

  @override
  String get batterySaverMode => 'وضع توفير البطارية';

  @override
  String get checkEvery60120sLowBatteryUsage =>
      'التحقق كل 60-120 ثانية (استهلاك منخفض للبطارية)';

  @override
  String get evaluationFrequencySetTo => 'تم تعيين تردد التقييم إلى';

  @override
  String get controlsTheMainGeofenceMonitoringService =>
      'يتحكم في خدمة مراقبة السياج الجغرافي الرئيسية. عند التعطيل، لن يتم الكشف عن أحداث السياج الجغرافي.';

  @override
  String get allowsTheAppToDetectGeofenceEvents =>
      'يسمح للتطبيق باكتشاف أحداث السياج الجغرافي حتى عند إغلاقه. بدون هذا الإذن، تعمل المراقبة فقط أثناء فتح التطبيق.';

  @override
  String get automaticallyAdjustsGeofenceCheckFrequency =>
      'يضبط تلقائيًا تردد فحص السياج الجغرافي بناءً على مستوى البطارية وحركة الجهاز لتوفير الطاقة.';

  @override
  String get chooseHowYouWantToBeNotified =>
      'اختر كيف تريد أن يتم إعلامك بأحداث السياج الجغرافي. الإشعارات المحلية تعمل بدون اتصال، الإشعارات الدفع تتطلب شبكة.';

  @override
  String get howOftenTheAppChecks =>
      'عدد المرات التي يتحقق فيها التطبيق من وجود الأجهزة داخل السياج الجغرافي. تردد أعلى = استهلاك أكبر للبطارية ولكن اكتشاف أسرع.';
}
