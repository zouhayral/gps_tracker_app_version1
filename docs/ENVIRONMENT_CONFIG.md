# Environment Configuration Guide

This document explains how to configure environment-specific settings for development, staging, and production builds.

## Overview

The app uses `--dart-define` to pass environment variables at build time. This approach:
- ✅ Keeps sensitive data out of source control
- ✅ Allows different configurations per environment
- ✅ Works with all Flutter platforms (web, mobile, desktop)

## Configuration Files

### `.env.example`
Template showing all available environment variables. **Check this into git**.

### `.env.development`
Development environment settings (local/test servers). **Add to .gitignore**.

### `.env.production`
Production environment settings (live servers). **Add to .gitignore**.

## Available Variables

### Traccar Server
```bash
TRACCAR_BASE_URL=http://your-server:8082
```
The base URL of your Traccar server. Used for API calls and WebSocket connections.

### Security
```bash
ALLOW_INSECURE=false
```
Set to `true` only for development with self-signed certificates. **Must be `false` in production**.

### Firebase (Future)
```bash
FIREBASE_API_KEY=your_api_key
FIREBASE_PROJECT_ID=your_project_id
FIREBASE_APP_ID=your_app_id
FIREBASE_MESSAGING_SENDER_ID=your_sender_id
```
Firebase configuration for push notifications and analytics.

## Build Commands

### Development Build
```bash
# Web
flutter build web --release --wasm \
  --dart-define=TRACCAR_BASE_URL=http://37.60.238.215:8082 \
  --dart-define=ALLOW_INSECURE=true

# Android
flutter build apk --release \
  --dart-define=TRACCAR_BASE_URL=http://37.60.238.215:8082 \
  --dart-define=ALLOW_INSECURE=true

# iOS
flutter build ios --release \
  --dart-define=TRACCAR_BASE_URL=http://37.60.238.215:8082 \
  --dart-define=ALLOW_INSECURE=true
```

### Production Build
```bash
# Web
flutter build web --release --wasm \
  --dart-define=TRACCAR_BASE_URL=https://your-production-server.com \
  --dart-define=ALLOW_INSECURE=false

# Android
flutter build apk --release \
  --dart-define=TRACCAR_BASE_URL=https://your-production-server.com \
  --dart-define=ALLOW_INSECURE=false

# iOS
flutter build ios --release \
  --dart-define=TRACCAR_BASE_URL=https://your-production-server.com \
  --dart-define=ALLOW_INSECURE=false
```

### Using Environment Files (with `--dart-define-from-file`)

Flutter 3.7+ supports loading variables from JSON files:

1. Create `env.development.json`:
```json
{
  "TRACCAR_BASE_URL": "http://37.60.238.215:8082",
  "ALLOW_INSECURE": "true"
}
```

2. Create `env.production.json`:
```json
{
  "TRACCAR_BASE_URL": "https://your-production-server.com",
  "ALLOW_INSECURE": "false"
}
```

3. Build with environment file:
```bash
# Development
flutter build web --release --wasm --dart-define-from-file=env.development.json

# Production
flutter build web --release --wasm --dart-define-from-file=env.production.json
```

## CI/CD Integration

### GitHub Actions
Update `.github/workflows/web-ci.yml`:

```yaml
- name: Build web (staging)
  run: flutter build web --release --wasm \
    --dart-define=TRACCAR_BASE_URL=${{ secrets.STAGING_TRACCAR_URL }} \
    --dart-define=ALLOW_INSECURE=false

- name: Build web (production)
  if: github.ref == 'refs/heads/main'
  run: flutter build web --release --wasm \
    --dart-define=TRACCAR_BASE_URL=${{ secrets.PROD_TRACCAR_URL }} \
    --dart-define=ALLOW_INSECURE=false
```

Add secrets in GitHub repo settings:
- `STAGING_TRACCAR_URL`
- `PROD_TRACCAR_URL`

### Firebase Hosting

Create `firebase.json` with multiple environments:

```json
{
  "hosting": [
    {
      "target": "staging",
      "public": "build/web",
      "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
      "rewrites": [
        {
          "source": "**",
          "destination": "/index.html"
        }
      ]
    },
    {
      "target": "production",
      "public": "build/web",
      "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
      "rewrites": [
        {
          "source": "**",
          "destination": "/index.html"
        }
      ]
    }
  ]
}
```

Deploy:
```bash
# Staging
firebase deploy --only hosting:staging

# Production
firebase deploy --only hosting:production
```

## Vercel Deployment

### Install Vercel CLI
```bash
npm i -g vercel
```

### Deploy with Environment Variables
```bash
# Set environment variables
vercel env add TRACCAR_BASE_URL production
# Enter: https://your-production-server.com

# Build and deploy
flutter build web --release --wasm \
  --dart-define=TRACCAR_BASE_URL=https://your-production-server.com \
  --dart-define=ALLOW_INSECURE=false

vercel --prod
```

### `vercel.json` Configuration
```json
{
  "buildCommand": "flutter build web --release --wasm --dart-define=TRACCAR_BASE_URL=$TRACCAR_BASE_URL",
  "outputDirectory": "build/web",
  "framework": null,
  "rewrites": [
    {
      "source": "/(.*)",
      "destination": "/index.html"
    }
  ],
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        {
          "key": "X-Content-Type-Options",
          "value": "nosniff"
        },
        {
          "key": "X-Frame-Options",
          "value": "DENY"
        },
        {
          "key": "X-XSS-Protection",
          "value": "1; mode=block"
        }
      ]
    }
  ]
}
```

## Security Best Practices

### ❌ Don't Do This
```dart
// NEVER hardcode secrets in source files
const apiKey = 'sk_live_xxxxxxxxxxxxx';
const serverUrl = 'https://production-server.com';
```

### ✅ Do This
```dart
// Use environment variables
const apiKey = String.fromEnvironment('API_KEY', defaultValue: '');
const serverUrl = String.fromEnvironment('TRACCAR_BASE_URL', 
  defaultValue: 'http://localhost:8082');

// Validate at runtime
if (apiKey.isEmpty) {
  throw Exception('API_KEY not configured');
}
```

### Gitignore
Add to `.gitignore`:
```gitignore
# Environment files with secrets
.env.development
.env.production
.env.local
env.*.json

# Firebase
.firebaserc
firebase-debug.log
```

## Accessing Variables in Code

The variables are already accessible in `lib/services/auth_service.dart`:

```dart
const rawBase = String.fromEnvironment(
  'TRACCAR_BASE_URL',
  defaultValue: 'http://37.60.238.215:8082',
);
const allowInsecure = bool.fromEnvironment('ALLOW_INSECURE');
```

To access in other files:
```dart
class MyConfig {
  static const traccarUrl = String.fromEnvironment(
    'TRACCAR_BASE_URL',
    defaultValue: 'http://localhost:8082',
  );
  
  static const isProduction = bool.fromEnvironment(
    'PRODUCTION',
    defaultValue: false,
  );
  
  static const enableAnalytics = bool.fromEnvironment(
    'ENABLE_ANALYTICS',
    defaultValue: true,
  );
}
```

## Testing Different Environments

### Local Development
```bash
flutter run --dart-define=TRACCAR_BASE_URL=http://localhost:8082
```

### Remote Development Server
```bash
flutter run --dart-define=TRACCAR_BASE_URL=http://37.60.238.215:8082
```

### Production Testing
```bash
flutter run --dart-define=TRACCAR_BASE_URL=https://your-production-server.com \
  --dart-define=PRODUCTION=true
```

## Troubleshooting

### "No environment variables found"
- Ensure you're passing `--dart-define` flags during build
- Check that variable names match exactly (case-sensitive)

### "Connection refused" errors
- Verify `TRACCAR_BASE_URL` is correct
- Check firewall/network settings
- For web builds, ensure CORS is configured on server

### Different behavior dev vs prod
- Print environment variables at app startup to verify:
```dart
void main() {
  const url = String.fromEnvironment('TRACCAR_BASE_URL');
  debugPrint('Using Traccar URL: $url');
  runApp(MyApp());
}
```

## Related Documentation

- [Flutter Environment Variables](https://flutter.dev/docs/deployment/flavors)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Firebase Hosting](https://firebase.google.com/docs/hosting)
- [Vercel Deployment](https://vercel.com/docs)
