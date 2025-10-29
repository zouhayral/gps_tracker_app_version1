// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Suivi GPS';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get reportsTitle => 'Rapports et Statistiques';

  @override
  String get reportsSubtitle => 'Voir les trajets, vitesses et distances';

  @override
  String get period => 'Période';

  @override
  String get device => 'Appareil';

  @override
  String get distance => 'Distance';

  @override
  String get avgSpeed => 'Vitesse moy.';

  @override
  String get maxSpeed => 'Vitesse max';

  @override
  String get trips => 'Trajets';

  @override
  String get language => 'Langue';

  @override
  String get languageSubtitle => 'Sélectionnez la langue de l\'application';

  @override
  String get noData => 'Aucune donnée disponible';

  @override
  String get refresh => 'Actualiser';

  @override
  String get exportShareReport => 'Exporter et partager le rapport';

  @override
  String get selectDevice => 'Sélectionner un appareil';

  @override
  String get noDevicesAvailable => 'Aucun appareil disponible';

  @override
  String get pleaseSelectDevice => 'Veuillez sélectionner un appareil';

  @override
  String get noDeviceSelected =>
      'Aucun appareil n\'est actuellement sélectionné';

  @override
  String get loadingStatistics => 'Chargement des statistiques...';

  @override
  String get loadingError => 'Erreur de chargement';

  @override
  String get retry => 'Réessayer';

  @override
  String get noTripsRecorded => 'Aucun trajet enregistré pour cette période';

  @override
  String get day => 'Jour';

  @override
  String get week => 'Semaine';

  @override
  String get month => 'Mois';

  @override
  String get custom => 'Personnalisé';

  @override
  String get editPeriod => 'Modifier la période';

  @override
  String get generatingPdf => 'Génération du PDF...';

  @override
  String get reportSharedSuccessfully => 'Rapport partagé avec succès';

  @override
  String get errorSharingReport => 'Erreur lors du partage du rapport';

  @override
  String get noDataToExport => 'Aucune donnée à exporter';

  @override
  String get fuelUsed => 'Carburant utilisé';

  @override
  String get speedEvolution => 'Évolution de la vitesse';

  @override
  String get tripDistribution => 'Répartition des trajets';

  @override
  String get periodSummary => 'Résumé de la période';

  @override
  String get start => 'Début';

  @override
  String get end => 'Fin';

  @override
  String get duration => 'Durée';

  @override
  String get account => 'Compte';

  @override
  String get notSignedIn => 'Non connecté';

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationsSubtitle =>
      'Désactiver pour arrêter de recevoir des alertes en direct. Vous pouvez toujours les consulter dans l\'onglet Alertes.';

  @override
  String get analyticsReports => 'Analyses et Rapports';

  @override
  String get geofences => 'Géo-clôtures';

  @override
  String get manageGeofences => 'Gérer les géo-clôtures';

  @override
  String get manageGeofencesSubtitle =>
      'Créer, modifier ou configurer les paramètres des géo-clôtures';

  @override
  String get languageDeveloperTools => 'Langue et outils de développement';

  @override
  String get currentLanguage => 'Actuel';

  @override
  String get selectLanguage => 'Sélectionner la langue';

  @override
  String get localeTest => 'Test de langue';

  @override
  String get localeTestSubtitle => 'Vérifier la configuration de localisation';

  @override
  String get logout => 'Déconnexion';

  @override
  String get loggedOut => 'Déconnecté';

  @override
  String get cancel => 'Annuler';

  @override
  String get time => 'Temps';

  @override
  String get speed => 'Vitesse (km/h)';

  @override
  String get numberOfTrips => 'Nombre de trajets';

  @override
  String tripCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trajets',
      one: '1 trajet',
      zero: 'Aucun trajet',
    );
    return '$_temp0';
  }

  @override
  String get chartsNotIncluded => 'Graphiques non inclus';

  @override
  String get generatedOn => 'Généré le';

  @override
  String get mainStatistics => 'Statistiques principales';

  @override
  String get metric => 'Métrique';

  @override
  String get value => 'Valeur';

  @override
  String get periodDetails => 'Détails de la période';

  @override
  String get mapTitle => 'Carte';

  @override
  String get tripsTitle => 'Trajets';

  @override
  String get notificationsTitle => 'Alertes';

  @override
  String get allDevices => 'Tous les appareils';

  @override
  String get noUpdateYet => 'Pas encore de mise à jour';

  @override
  String get updated => 'Mis à jour';

  @override
  String get refreshData => 'Actualiser les données';

  @override
  String get dataRefreshedSuccessfully => 'Données actualisées avec succès';

  @override
  String get refreshFailed => 'Échec de l\'actualisation';

  @override
  String get mapLayer => 'Couche de carte';

  @override
  String get openInMaps => 'Ouvrir dans Cartes';

  @override
  String get noValidCoordinates =>
      'Aucune coordonnée valide disponible pour cet appareil';

  @override
  String get failedToOpenMaps => 'Échec de l\'ouverture de la carte';

  @override
  String get failedToLoadDevices =>
      'Échec du chargement des appareils pour la carte';

  @override
  String get loadingMapTiles => 'Chargement des tuiles de carte...';

  @override
  String get loadingFleetData => 'Chargement des données de la flotte...';

  @override
  String get failedToLoadFleetData =>
      'Échec du chargement des données de la flotte';

  @override
  String get liveTracking => 'Suivi en direct';

  @override
  String get centerMap => 'Centrer la carte';

  @override
  String get deviceOffline => 'Appareil hors ligne';

  @override
  String get noDevicesFound => 'Aucun appareil trouvé';

  @override
  String get engineAndMovement => 'Moteur et mouvement';

  @override
  String get engine => 'Moteur';

  @override
  String get speedKmh => 'Vitesse (km/h)';

  @override
  String get lastLocation => 'Dernière position';

  @override
  String get coordinates => 'Coordonnées';

  @override
  String get noLocationData => 'Aucune donnée de localisation disponible';

  @override
  String get devicesSelected => 'appareils sélectionnés';

  @override
  String get online => 'En ligne';

  @override
  String get offline => 'Hors ligne';

  @override
  String get unknown => 'Inconnu';

  @override
  String get more => 'de plus';

  @override
  String get filterYourTrips => 'Filtrer Vos Trajets';

  @override
  String get filterDescription =>
      'Sélectionnez les appareils et la plage de dates pour voir les trajets';

  @override
  String get applyFilter => 'Appliquer le Filtre';

  @override
  String get quickAllDevices => 'Rapide: Tous les Appareils (24h)';

  @override
  String get noTripsFound => 'Aucun trajet trouvé';

  @override
  String get filterTripsTitle => 'Filtrer les trajets';

  @override
  String get dateRange => 'Plage de dates';

  @override
  String get devices => 'Appareils';

  @override
  String devicesAvailable(Object count) {
    return '$count appareils disponibles';
  }

  @override
  String get tripSummary => 'Résumé des trajets';

  @override
  String get viewDetails => 'Voir les détails';

  @override
  String get alertsTitle => 'Alertes';

  @override
  String get noAlerts => 'Aucune alerte pour le moment';

  @override
  String get markAllRead => 'Tout marquer comme lu';

  @override
  String get clearAll => 'Tout effacer';

  @override
  String get refreshingAlerts => 'Actualisation des alertes...';

  @override
  String get failedToLoadAlerts => 'Échec du chargement des alertes';

  @override
  String get newEventsWillAppear => 'Les nouveaux événements apparaîtront ici';

  @override
  String get markAll => 'Tout marquer';

  @override
  String get deleteAll => 'Tout supprimer';

  @override
  String get deleteAllNotifications => 'Supprimer toutes les notifications ?';

  @override
  String get deleteAllNotificationsConfirm =>
      'Cela supprimera définitivement toutes les notifications de cet appareil.';

  @override
  String get allNotificationsDeleted =>
      'Toutes les notifications ont été supprimées';

  @override
  String get delete => 'Supprimer';

  @override
  String get close => 'Fermer';

  @override
  String get message => 'Message';

  @override
  String get deviceId => 'ID de l\'appareil';

  @override
  String get severity => 'Gravité';

  @override
  String get ignitionOn => 'Contact mis';

  @override
  String get ignitionOff => 'Contact coupé';

  @override
  String get deviceOnline => 'Appareil en ligne';

  @override
  String get geofenceEnter => 'Entrée dans la zone';

  @override
  String get geofenceExit => 'Sortie de la zone';

  @override
  String get alarm => 'Alarme';

  @override
  String get overspeed => 'Excès de vitesse';

  @override
  String get maintenanceDue => 'Maintenance requise';

  @override
  String get deviceMoving => 'Appareil en mouvement';

  @override
  String get deviceStopped => 'Appareil arrêté';

  @override
  String get speedAlert => 'Alerte de vitesse';

  @override
  String get vehicleStopped => 'Véhicule arrêté';

  @override
  String get vehicleMoving => 'Véhicule en mouvement';

  @override
  String get vehicleStarted => 'Véhicule démarré';

  @override
  String get unknownDevice => 'Appareil inconnu';

  @override
  String get alertDetails => 'Détails de l\'alerte';

  @override
  String get triggeredAt => 'Déclenchée à';

  @override
  String get type => 'Type';

  @override
  String get location => 'Emplacement';

  @override
  String get basicInformation => 'Informations de base';

  @override
  String get name => 'Nom';

  @override
  String get description => 'Description';

  @override
  String get optional => 'optionnel';

  @override
  String get allDevicesLabel => 'Tous les appareils';

  @override
  String get createGeofence => 'Créer une géobarrière';

  @override
  String get save => 'Enregistrer';

  @override
  String get triggers => 'Déclencheurs';

  @override
  String get polygon => 'Polygone';

  @override
  String get circle => 'Cercle';

  @override
  String get drawBoundary => 'Dessiner la limite';

  @override
  String get useCurrentLocation => 'Utiliser l\'emplacement actuel';

  @override
  String get radius => 'Rayon';

  @override
  String get onEnter => 'À l\'entrée';

  @override
  String get onExit => 'À la sortie';

  @override
  String get dwellTime => 'Temps de séjour';

  @override
  String get monitoredDevices => 'Appareils surveillés';

  @override
  String get sound => 'Son';

  @override
  String get vibration => 'Vibration';

  @override
  String get priority => 'Priorité';

  @override
  String get defaultPriority => 'Par défaut';

  @override
  String get both => 'Les deux';

  @override
  String get push => 'Push';

  @override
  String get local => 'Local';

  @override
  String get triggerWhenDeviceEnters =>
      'Déclencher quand l\'appareil entre dans cette zone';

  @override
  String get triggerWhenDeviceLeaves =>
      'Déclencher quand l\'appareil quitte cette zone';

  @override
  String get triggerWhenDeviceStays =>
      'Déclencher quand l\'appareil reste dans la zone';

  @override
  String get monitorAllDevices =>
      'Surveiller tous les appareils automatiquement';

  @override
  String get selectAtLeastOneDevice =>
      'Sélectionner au moins un appareil ou activer \"Tous les appareils\"';

  @override
  String get playNotificationSound => 'Jouer le son de notification';

  @override
  String get vibrateOnNotification => 'Vibrer lors de la notification';

  @override
  String get paused => 'En pause';

  @override
  String get active => 'Actif';

  @override
  String get total => 'Total';

  @override
  String get entry => 'Entrée';

  @override
  String get exit => 'Sortie';

  @override
  String get welcomeBack => 'bienvenue';

  @override
  String get enterYourAccount => 'Entrez votre compte';

  @override
  String get emailOrUsername => 'Email ou nom d\'utilisateur';

  @override
  String get password => 'Mot de passe';

  @override
  String get login => 'connexion';

  @override
  String get enterEmailOrUsername => 'Entrez l\'email ou le nom d\'utilisateur';

  @override
  String get enterPassword => 'Entrez le mot de passe';

  @override
  String get sessionExpired => 'Session expirée';

  @override
  String get pleaseEnterPasswordToContinue =>
      'Veuillez entrer votre mot de passe pour continuer';

  @override
  String get validatingSession => 'Validation de votre session...';

  @override
  String get imageNotFound => 'Image introuvable';

  @override
  String get geofenceSettings => 'Paramètres de géorepérage';

  @override
  String get aboutGeofenceSettings => 'À propos des paramètres de géorepérage';

  @override
  String get geofenceConfiguration => 'Configuration du géorepérage';

  @override
  String get configureHowGeofencesWork =>
      'Configurez le fonctionnement des géorepérages, y compris la surveillance, les notifications et l\'optimisation des performances.';

  @override
  String get enableGeofencing => 'Activer le géorepérage';

  @override
  String get turnOnToReceiveAlerts =>
      'Activez pour recevoir des alertes lors de l\'entrée ou de la sortie des géorepérages';

  @override
  String get signInToEnableGeofenceMonitoring =>
      'Connectez-vous pour activer la surveillance du géorepérage';

  @override
  String get backgroundGeofenceMonitoringActive =>
      'La surveillance et les notifications de géorepérage en arrière-plan sont actives';

  @override
  String get backgroundAccess => 'Accès en arrière-plan';

  @override
  String get backgroundGeofenceMonitoringEnabled =>
      'Surveillance du géorepérage en arrière-plan activée';

  @override
  String get disabledAppMayMissEvents =>
      'Désactivé – l\'application peut manquer des événements lorsqu\'elle est fermée';

  @override
  String get backgroundAccessGranted => '✅ Accès en arrière-plan accordé';

  @override
  String get foregroundOnlyModeActivated =>
      '⚠️ Mode premier plan uniquement activé';

  @override
  String get aboutForegroundMode => 'À propos du mode premier plan';

  @override
  String get inForegroundOnlyMode =>
      'En mode premier plan uniquement, la surveillance du géorepérage ne fonctionne que lorsque l\'application est ouverte. Pour recevoir des alertes lorsque l\'application est fermée, activez l\'accès à la localisation en arrière-plan.';

  @override
  String get gotIt => 'Compris';

  @override
  String get adaptiveOptimization => 'Optimisation adaptative';

  @override
  String get disabledFixedEvaluationFrequency =>
      'Désactivé - Fréquence d\'évaluation fixe';

  @override
  String get activeMode => 'Mode actif';

  @override
  String get idleMode => 'Mode inactif';

  @override
  String get batterySaver => 'Économiseur de batterie';

  @override
  String get interval => 'intervalle';

  @override
  String get optimizationDisabled => 'Optimisation désactivée';

  @override
  String get adaptiveOptimizationEnabled => '✅ Optimisation adaptative activée';

  @override
  String get adaptiveOptimizationDisabled =>
      '⏸️ Optimisation adaptative désactivée';

  @override
  String get failedToStartOptimizer => '❌ Échec du démarrage de l\'optimiseur';

  @override
  String get optimizationStatistics => 'Statistiques d\'optimisation';

  @override
  String get savings => 'Économies';

  @override
  String get defaultNotificationType => 'Type de notification par défaut';

  @override
  String get localOnly => 'Local uniquement';

  @override
  String get evaluationFrequency => 'Fréquence d\'évaluation';

  @override
  String get balancedRecommended => 'Équilibré (recommandé)';

  @override
  String get resetToDefaults => 'Réinitialiser aux valeurs par défaut';

  @override
  String get thisWillResetAllGeofenceSettings =>
      'Cela réinitialisera tous les paramètres de géorepérage à leurs valeurs par défaut. Êtes-vous sûr de vouloir continuer ?';

  @override
  String get reset => 'Réinitialiser';

  @override
  String get settingsResetToDefaults =>
      '✅ Paramètres réinitialisés aux valeurs par défaut';

  @override
  String get geofenceMonitoringStarted =>
      '✅ Surveillance du géorepérage démarrée';

  @override
  String get geofenceMonitoringStopped =>
      '⏸️ Surveillance du géorepérage arrêtée';

  @override
  String get failedToStartMonitoring =>
      '❌ Échec du démarrage de la surveillance';

  @override
  String get failedToStopMonitoring => '❌ Échec de l\'arrêt de la surveillance';

  @override
  String get selectNotificationType => 'Sélectionner le type de notification';

  @override
  String get showNotificationsOnlyOnThisDevice =>
      'Afficher les notifications uniquement sur cet appareil';

  @override
  String get pushOnly => 'Push uniquement';

  @override
  String get sendPushNotificationsViaServer =>
      'Envoyer des notifications push via le serveur (nécessite une connexion réseau)';

  @override
  String get bothLocalPush => 'Les deux (Local + Push)';

  @override
  String get sendBothLocalAndPushNotifications =>
      'Envoyer des notifications locales et push';

  @override
  String get silent => 'Silencieux';

  @override
  String get noNotificationsEventsStillLogged =>
      'Aucune notification (les événements sont toujours enregistrés)';

  @override
  String get notificationTypeSetTo => 'Type de notification défini sur';

  @override
  String get selectEvaluationFrequency =>
      'Sélectionner la fréquence d\'évaluation';

  @override
  String get fastRealTime => 'Rapide (Temps réel)';

  @override
  String get checkEvery510sHighBatteryUsage =>
      'Vérifier toutes les 5-10s (consommation de batterie élevée)';

  @override
  String get checkEvery30sModerateBatteryUsage =>
      'Vérifier toutes les 30s (consommation de batterie modérée)';

  @override
  String get batterySaverMode => 'Mode économie de batterie';

  @override
  String get checkEvery60120sLowBatteryUsage =>
      'Vérifier toutes les 60-120s (faible consommation de batterie)';

  @override
  String get evaluationFrequencySetTo => 'Fréquence d\'évaluation définie sur';

  @override
  String get controlsTheMainGeofenceMonitoringService =>
      'Contrôle le service principal de surveillance du géorepérage. Lorsqu\'il est désactivé, aucun événement de géorepérage ne sera détecté.';

  @override
  String get allowsTheAppToDetectGeofenceEvents =>
      'Permet à l\'application de détecter les événements de géorepérage même lorsqu\'elle est fermée. Sans cette autorisation, la surveillance ne fonctionne que lorsque l\'application est ouverte.';

  @override
  String get automaticallyAdjustsGeofenceCheckFrequency =>
      'Ajuste automatiquement la fréquence de vérification du géorepérage en fonction du niveau de batterie et du mouvement de l\'appareil pour économiser de l\'énergie.';

  @override
  String get chooseHowYouWantToBeNotified =>
      'Choisissez comment vous souhaitez être notifié des événements de géorepérage. Les notifications locales fonctionnent hors ligne, les notifications push nécessitent une connexion réseau.';

  @override
  String get howOftenTheAppChecks =>
      'À quelle fréquence l\'application vérifie si les appareils sont à l\'intérieur des géorepérages. Fréquence plus élevée = plus de consommation de batterie mais détection plus rapide.';
}
