# Deployment & Monitoring Setup Guide

## Overview
Complete guide for deploying the GPS Tracker web app to production and setting up monitoring infrastructure.

---

## 1. Stage Deployment

### Firebase Hosting Setup

#### Prerequisites
```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize Firebase (if not done)
firebase init hosting
```

#### Configure GitHub Secrets
Add these secrets to your repository (Settings → Secrets and variables → Actions):

1. **FIREBASE_SERVICE_ACCOUNT**: 
   - Go to Firebase Console → Project Settings → Service Accounts
   - Generate new private key
   - Copy the entire JSON content
   - Add as GitHub secret

2. **FIREBASE_PROJECT_ID**:
   - Your Firebase project ID (e.g., `gps-tracker-prod`)

3. **GITHUB_TOKEN**:
   - Automatically provided by GitHub Actions

#### Deploy Manually
```bash
# Development/Staging
./scripts/deploy-firebase.sh staging

# Production
./scripts/deploy-firebase.sh production
```

#### Deploy via CI/CD
```bash
# Push to main branch → triggers production deployment
git push origin main

# Open PR → triggers staging preview deployment
git checkout -b feature/new-feature
git push origin feature/new-feature
# Create PR on GitHub
```

### Vercel Setup

#### Prerequisites
```bash
# Install Vercel CLI
npm install -g vercel

# Login to Vercel
vercel login
```

#### Configure GitHub Integration
1. Go to Vercel dashboard
2. Import Git Repository
3. Connect your GitHub repo
4. Configure build settings:
   - **Framework Preset**: Other
   - **Build Command**: `flutter build web --release --wasm --dart-define=TRACCAR_BASE_URL=$TRACCAR_BASE_URL`
   - **Output Directory**: `build/web`
5. Add environment variables:
   - `TRACCAR_BASE_URL`
   - `ALLOW_INSECURE`

#### Deploy Manually
```bash
# Development/Staging
./scripts/deploy-vercel.sh staging

# Production
./scripts/deploy-vercel.sh production
```

---

## 2. Smoke Testing

### Local Testing
```bash
# Install dependencies
npm install

# Run local server
python -m http.server 8080 -d build/web

# Run smoke tests
npm run smoke-test
```

### Staging Testing
```bash
# Test staging deployment
npm run smoke-test:staging
```

### Production Testing
```bash
# Test production deployment
npm run smoke-test:production
```

### Manual Testing Checklist

#### Route Testing
- [ ] `/` - Login page loads
- [ ] `/dashboard` - Dashboard displays (after auth)
- [ ] `/map` - Map renders correctly
- [ ] `/device/:id` - Device detail shows data
- [ ] `/trips` - Trip history loads
- [ ] `/geofences` - Geofence list displays
- [ ] `/geofences/events` - Events page shows history
- [ ] `/analytics` - Analytics charts render
- [ ] `/settings` - Settings page accessible
- [ ] `/alerts` - Alerts page loads

#### Deep Link Testing
- [ ] Direct URL navigation works (e.g., `/dashboard`)
- [ ] Browser refresh maintains route
- [ ] Back/forward buttons work correctly
- [ ] Deep links from external sources work

#### Service Worker Testing
1. Open DevTools → Application → Service Workers
2. Check registrations:
   - [ ] `flutter_service_worker.js` registered
   - [ ] Service worker status: "activated and running"
3. Test offline mode:
   - [ ] Check "Offline" in DevTools
   - [ ] App shell loads from cache
   - [ ] Graceful error for network requests

#### Performance Testing
- [ ] Lighthouse score > 90 for Performance
- [ ] First Contentful Paint < 2s
- [ ] Time to Interactive < 3.5s
- [ ] No console errors
- [ ] No 404 errors in Network tab

---

## 3. Monitoring Setup

### Sentry Integration (Error Tracking)

#### 1. Create Sentry Account
- Go to [sentry.io](https://sentry.io)
- Create new project (Flutter/Dart)
- Copy DSN

#### 2. Add Sentry Package
```yaml
# pubspec.yaml
dependencies:
  sentry_flutter: ^7.14.0
```

#### 3. Initialize Sentry
```dart
// lib/main.dart
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment(
        'SENTRY_DSN',
        defaultValue: '',
      );
      options.environment = const String.fromEnvironment(
        'ENVIRONMENT',
        defaultValue: 'development',
      );
      options.tracesSampleRate = 0.2;
      options.enableAutoSessionTracking = true;
      options.attachScreenshot = true;
      options.attachViewHierarchy = true;
    },
    appRunner: () => runApp(const MyApp()),
  );
}
```

#### 4. Build with Sentry
```bash
flutter build web --release --wasm \
  --dart-define=SENTRY_DSN=your-sentry-dsn \
  --dart-define=ENVIRONMENT=production
```

#### 5. Configure Alerts
- Go to Sentry → Alerts
- Create alert rules:
  - New issue created
  - Error rate exceeds threshold
  - Performance degradation
- Configure notification channels (Email, Slack, PagerDuty)

### Firebase Analytics

#### 1. Enable Firebase Analytics
```bash
firebase init analytics
```

#### 2. Add Firebase Package
```yaml
# pubspec.yaml
dependencies:
  firebase_core: ^2.24.2
  firebase_analytics: ^10.8.0
```

#### 3. Initialize Firebase
```dart
// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(const MyApp());
}

// Track custom events
class AnalyticsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  
  Future<void> logGeofenceCreated() async {
    await _analytics.logEvent(
      name: 'geofence_created',
      parameters: {'timestamp': DateTime.now().toIso8601String()},
    );
  }
  
  Future<void> logDeviceSelected(String deviceId) async {
    await _analytics.logEvent(
      name: 'device_selected',
      parameters: {'device_id': deviceId},
    );
  }
}
```

#### 4. Track Page Views
```dart
// With GoRouter
GoRouter(
  observers: [FirebaseAnalyticsObserver(analytics: analytics)],
  routes: [...],
);
```

### Google Analytics (Alternative)

#### 1. Create GA4 Property
- Go to [analytics.google.com](https://analytics.google.com)
- Create new GA4 property
- Copy Measurement ID (G-XXXXXXXXXX)

#### 2. Add GA Tag to index.html
```html
<!-- web/index.html -->
<head>
  <!-- Google tag (gtag.js) -->
  <script async src="https://www.googletagmanager.com/gtag/js?id=G-XXXXXXXXXX"></script>
  <script>
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    gtag('js', new Date());
    gtag('config', 'G-XXXXXXXXXX');
  </script>
</head>
```

### Uptime Monitoring

#### UptimeRobot (Free Tier)
1. Go to [uptimerobot.com](https://uptimerobot.com)
2. Create new monitor:
   - **Type**: HTTP(s)
   - **URL**: Your production URL
   - **Interval**: 5 minutes
   - **Timeout**: 30 seconds
3. Configure alerts:
   - Email notifications
   - SMS (optional)
   - Webhook integration

#### Firebase Performance Monitoring
```yaml
# pubspec.yaml
dependencies:
  firebase_performance: ^0.9.3
```

```dart
// lib/main.dart
import 'package:firebase_performance/firebase_performance.dart';

Future<void> trackNetworkRequest() async {
  final metric = FirebasePerformance.instance.newHttpMetric(
    'https://api.example.com/data',
    HttpMethod.Get,
  );
  
  await metric.start();
  // Make network request
  await metric.stop();
}
```

### Crashlytics Setup

#### 1. Enable Crashlytics
```bash
firebase init crashlytics
```

#### 2. Add Package
```yaml
# pubspec.yaml
dependencies:
  firebase_crashlytics: ^3.4.9
```

#### 3. Initialize Crashlytics
```dart
// lib/main.dart
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Pass all uncaught errors to Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
  
  runZonedGuarded(() {
    runApp(const MyApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack);
  });
}

// Custom crash reporting
Future<void> reportError(String context, dynamic error, StackTrace stack) async {
  await FirebaseCrashlytics.instance.recordError(
    error,
    stack,
    reason: context,
    fatal: false,
  );
}
```

---

## 4. Monitoring Dashboard

### Key Metrics to Track

#### Application Performance
- **Page Load Time**: Target < 2s
- **Time to Interactive**: Target < 3.5s
- **First Contentful Paint**: Target < 1.5s
- **Cumulative Layout Shift**: Target < 0.1
- **Largest Contentful Paint**: Target < 2.5s

#### Error Rates
- **JavaScript Errors**: Target < 0.1%
- **HTTP 4xx Errors**: Target < 1%
- **HTTP 5xx Errors**: Target < 0.01%
- **Crash Rate**: Target < 0.01%

#### User Engagement
- **Daily Active Users (DAU)**
- **Session Duration**: Target > 5 minutes
- **Bounce Rate**: Target < 40%
- **Pages per Session**: Target > 3

#### Business Metrics
- **Geofences Created per Day**
- **Devices Monitored**
- **Alerts Triggered**
- **Average Response Time to Alerts**

### Setting Up Dashboards

#### Sentry Dashboard
1. Go to Sentry → Dashboards
2. Create custom dashboard with:
   - Error rate over time
   - Top 10 errors by frequency
   - Affected users
   - Error distribution by browser

#### Firebase Console
1. Go to Firebase Console → Analytics → Dashboards
2. Monitor:
   - User retention
   - Event tracking
   - Conversion funnels
   - User demographics

#### Google Analytics
1. Create custom dashboard:
   - Real-time users
   - Page views by route
   - User flow
   - Device breakdown

---

## 5. Post-Launch Checklist

### Immediate (Day 1)
- [ ] Verify production deployment successful
- [ ] Run smoke tests on production
- [ ] Verify all routes accessible
- [ ] Check service worker registration
- [ ] Monitor error rates (should be < 1%)
- [ ] Check performance metrics (Lighthouse)
- [ ] Test on multiple browsers
- [ ] Test on multiple devices
- [ ] Verify analytics tracking

### Short-term (Week 1)
- [ ] Review Sentry error reports daily
- [ ] Monitor uptime (target 99.9%)
- [ ] Analyze user behavior (GA4)
- [ ] Collect user feedback
- [ ] Review performance trends
- [ ] Check for browser-specific issues
- [ ] Monitor API error rates
- [ ] Review security headers

### Medium-term (Month 1)
- [ ] Conduct security audit
- [ ] Review and optimize performance
- [ ] Analyze feature usage
- [ ] Plan feature improvements
- [ ] Review and update documentation
- [ ] Optimize asset delivery (CDN)
- [ ] A/B test key features
- [ ] User satisfaction survey

---

## 6. Troubleshooting

### Deployment Issues

#### Build Fails
```bash
# Clear cache
flutter clean
flutter pub get

# Rebuild
flutter build web --release --wasm
```

#### 404 Errors on Refresh
- Verify SPA rewrites in `firebase.json` or `vercel.json`
- Check that all routes rewrite to `/index.html`

#### Service Worker Not Registering
- Check HTTPS is enabled
- Verify `flutter_service_worker.js` exists in build output
- Clear browser cache and hard reload

### Monitoring Issues

#### Sentry Not Reporting Errors
- Verify DSN is correct
- Check `--dart-define=SENTRY_DSN` in build command
- Test with `Sentry.captureException(Exception('Test'))`

#### Analytics Not Tracking
- Verify Firebase initialization
- Check browser console for errors
- Enable debug mode: `firebase.analytics().setAnalyticsCollectionEnabled(true)`

#### High Error Rates
1. Check Sentry for specific errors
2. Review recent deployments
3. Roll back if necessary:
   ```bash
   firebase hosting:rollback
   ```

---

## 7. Production Environment Variables

### Required Variables
```bash
# Build-time (--dart-define)
TRACCAR_BASE_URL=https://your-production-server.com
ALLOW_INSECURE=false
ENVIRONMENT=production
SENTRY_DSN=https://your-sentry-dsn@sentry.io/project-id

# Firebase (GitHub Secrets)
FIREBASE_SERVICE_ACCOUNT=<service-account-json>
FIREBASE_PROJECT_ID=your-project-id

# Vercel (Environment Variables in Dashboard)
TRACCAR_BASE_URL=https://your-production-server.com
ALLOW_INSECURE=false
```

### Security Best Practices
1. **Never commit secrets to Git**
2. **Use GitHub Secrets for CI/CD**
3. **Rotate credentials quarterly**
4. **Use least-privilege service accounts**
5. **Enable 2FA on all accounts**
6. **Monitor access logs**

---

## 8. Next Steps

1. **Configure GitHub Secrets** (FIREBASE_SERVICE_ACCOUNT, FIREBASE_PROJECT_ID)
2. **Deploy to staging** (`git push` to feature branch, create PR)
3. **Run smoke tests** (`npm run smoke-test:staging`)
4. **Merge to main** (triggers production deployment)
5. **Monitor metrics** (Sentry, GA4, UptimeRobot)
6. **Iterate based on data**

---

## Resources

- [Firebase Hosting Documentation](https://firebase.google.com/docs/hosting)
- [Vercel Documentation](https://vercel.com/docs)
- [Sentry Flutter Documentation](https://docs.sentry.io/platforms/flutter/)
- [Firebase Analytics Documentation](https://firebase.google.com/docs/analytics)
- [Google Analytics 4 Documentation](https://support.google.com/analytics/topic/9303319)
- [Flutter Web Performance](https://docs.flutter.dev/perf/web-performance)

---

**Last Updated**: January 2025  
**Version**: 1.0.0
