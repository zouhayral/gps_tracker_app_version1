const puppeteer = require('puppeteer');

// Configuration
const BASE_URL = process.env.BASE_URL || 'http://localhost:8080';
const TIMEOUT = 10000;

// Test routes
const ROUTES = [
  { path: '/', name: 'Login' },
  { path: '/dashboard', name: 'Dashboard', requiresAuth: true },
  { path: '/map', name: 'Map', requiresAuth: true },
  { path: '/device/1', name: 'Device Detail', requiresAuth: true },
  { path: '/trips', name: 'Trips', requiresAuth: true },
  { path: '/geofences', name: 'Geofences', requiresAuth: true },
  { path: '/geofences/events', name: 'Geofence Events', requiresAuth: true },
  { path: '/analytics', name: 'Analytics', requiresAuth: true },
  { path: '/settings', name: 'Settings', requiresAuth: true },
  { path: '/alerts', name: 'Alerts', requiresAuth: true },
];

// Smoke test results
const results = {
  passed: 0,
  failed: 0,
  errors: [],
};

async function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function testRoute(browser, route) {
  const page = await browser.newPage();
  
  try {
    console.log(`Testing ${route.name} (${route.path})...`);
    
    // Navigate to route
    const response = await page.goto(`${BASE_URL}${route.path}`, {
      waitUntil: 'networkidle2',
      timeout: TIMEOUT,
    });
    
    // Check response status
    if (!response.ok() && response.status() !== 304) {
      throw new Error(`HTTP ${response.status()}`);
    }
    
    // Wait for Flutter to initialize
    await delay(2000);
    
    // Check if page loaded (look for Flutter root)
    const hasFlutterRoot = await page.evaluate(() => {
      return document.querySelector('flt-glass-pane') !== null;
    });
    
    if (!hasFlutterRoot) {
      throw new Error('Flutter app did not initialize');
    }
    
    // For auth routes, check if redirected to login
    if (route.requiresAuth) {
      const currentUrl = page.url();
      // If redirected to login, that's expected behavior
      if (currentUrl.includes('/') && !currentUrl.includes(route.path)) {
        console.log(`  ✅ Correctly redirected to login`);
      } else {
        console.log(`  ✅ Page loaded (authenticated)`);
      }
    } else {
      console.log(`  ✅ Page loaded successfully`);
    }
    
    results.passed++;
    
  } catch (error) {
    console.log(`  ❌ Failed: ${error.message}`);
    results.failed++;
    results.errors.push({
      route: route.name,
      path: route.path,
      error: error.message,
    });
  } finally {
    await page.close();
  }
}

async function testServiceWorkers(browser) {
  const page = await browser.newPage();
  
  try {
    console.log('\nTesting Service Workers...');
    
    await page.goto(BASE_URL, {
      waitUntil: 'networkidle2',
      timeout: TIMEOUT,
    });
    
    // Wait for service workers to register
    await delay(3000);
    
    // Check service worker registration
    const serviceWorkers = await page.evaluate(async () => {
      if (!navigator.serviceWorker) {
        return { supported: false };
      }
      
      const registrations = await navigator.serviceWorker.getRegistrations();
      return {
        supported: true,
        count: registrations.length,
        scopes: registrations.map(reg => reg.scope),
      };
    });
    
    if (!serviceWorkers.supported) {
      console.log('  ⚠️  Service Workers not supported');
      return;
    }
    
    if (serviceWorkers.count === 0) {
      throw new Error('No service workers registered');
    }
    
    console.log(`  ✅ ${serviceWorkers.count} service worker(s) registered`);
    serviceWorkers.scopes.forEach(scope => {
      console.log(`     - ${scope}`);
    });
    
    results.passed++;
    
  } catch (error) {
    console.log(`  ❌ Failed: ${error.message}`);
    results.failed++;
    results.errors.push({
      route: 'Service Workers',
      error: error.message,
    });
  } finally {
    await page.close();
  }
}

async function testSPARewrite(browser) {
  const page = await browser.newPage();
  
  try {
    console.log('\nTesting SPA rewrites...');
    
    // Test a deep link that should rewrite to /index.html
    const response = await page.goto(`${BASE_URL}/dashboard`, {
      waitUntil: 'networkidle2',
      timeout: TIMEOUT,
    });
    
    // Check that we got a 200 response (not 404)
    if (response.status() === 404) {
      throw new Error('SPA rewrite failed - got 404');
    }
    
    // Check that index.html was served
    const content = await page.content();
    if (!content.includes('flutter') && !content.includes('flt-')) {
      throw new Error('SPA rewrite returned non-Flutter content');
    }
    
    console.log('  ✅ SPA rewrites working correctly');
    results.passed++;
    
  } catch (error) {
    console.log(`  ❌ Failed: ${error.message}`);
    results.failed++;
    results.errors.push({
      route: 'SPA Rewrites',
      error: error.message,
    });
  } finally {
    await page.close();
  }
}

async function testHTTPSRedirect() {
  console.log('\nTesting HTTPS redirect...');
  
  // Only test if BASE_URL is HTTPS
  if (!BASE_URL.startsWith('https://')) {
    console.log('  ⚠️  Skipped (not HTTPS environment)');
    return;
  }
  
  try {
    const httpUrl = BASE_URL.replace('https://', 'http://');
    const response = await fetch(httpUrl, { redirect: 'manual' });
    
    if (response.status === 301 || response.status === 302) {
      const location = response.headers.get('location');
      if (location && location.startsWith('https://')) {
        console.log('  ✅ HTTPS redirect working');
        results.passed++;
        return;
      }
    }
    
    throw new Error('HTTPS redirect not configured');
    
  } catch (error) {
    console.log(`  ❌ Failed: ${error.message}`);
    results.failed++;
    results.errors.push({
      route: 'HTTPS Redirect',
      error: error.message,
    });
  }
}

async function runSmokeTests() {
  console.log('🧪 Starting smoke tests...');
  console.log(`Base URL: ${BASE_URL}\n`);
  
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });
  
  try {
    // Test all routes
    for (const route of ROUTES) {
      await testRoute(browser, route);
    }
    
    // Test service workers
    await testServiceWorkers(browser);
    
    // Test SPA rewrites
    await testSPARewrite(browser);
    
    // Test HTTPS redirect
    await testHTTPSRedirect();
    
  } finally {
    await browser.close();
  }
  
  // Print summary
  console.log('\n' + '='.repeat(50));
  console.log('📊 Smoke Test Results');
  console.log('='.repeat(50));
  console.log(`Passed: ${results.passed}`);
  console.log(`Failed: ${results.failed}`);
  
  if (results.errors.length > 0) {
    console.log('\n❌ Errors:');
    results.errors.forEach(err => {
      console.log(`  - ${err.route}: ${err.error}`);
    });
  }
  
  // Exit with error code if any tests failed
  process.exit(results.failed > 0 ? 1 : 0);
}

// Run tests
runSmokeTests().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});
