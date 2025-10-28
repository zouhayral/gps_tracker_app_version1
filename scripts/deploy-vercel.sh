#!/bin/bash
# Deploy to Vercel (Staging or Production)
# Usage: ./deploy-vercel.sh [staging|production]

set -e  # Exit on error

ENVIRONMENT=${1:-staging}

echo "🚀 Deploying to Vercel ($ENVIRONMENT)..."

# Load environment variables
if [ "$ENVIRONMENT" = "production" ]; then
  TRACCAR_URL="https://your-production-server.com"
  ALLOW_INSECURE="false"
  PRODUCTION_FLAG="--prod"
else
  TRACCAR_URL="http://37.60.238.215:8082"
  ALLOW_INSECURE="true"
  PRODUCTION_FLAG=""
fi

echo "📦 Building Flutter web app..."
flutter build web --release --wasm \
  --dart-define=TRACCAR_BASE_URL=$TRACCAR_URL \
  --dart-define=ALLOW_INSECURE=$ALLOW_INSECURE \
  --dart-define=ENVIRONMENT=$ENVIRONMENT

echo "✅ Build complete!"

echo "🔍 Running pre-deployment checks..."
# Check if build directory exists
if [ ! -d "build/web" ]; then
  echo "❌ Build directory not found!"
  exit 1
fi

# Check if index.html exists
if [ ! -f "build/web/index.html" ]; then
  echo "❌ index.html not found in build!"
  exit 1
fi

echo "✅ Pre-deployment checks passed!"

echo "🚀 Deploying to Vercel ($ENVIRONMENT)..."
vercel deploy build/web $PRODUCTION_FLAG

echo "✅ Deployment complete!"
echo "🌐 Your app is now live!"

echo ""
echo "🧪 Next steps:"
echo "1. Run smoke tests: npm run smoke-test"
echo "2. Check service worker: Open DevTools → Application → Service Workers"
echo "3. Test deep links: Visit /dashboard, /map directly"
echo "4. Check logs: vercel logs"
