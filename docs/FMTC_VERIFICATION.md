/// FMTC Isolate Injection & Network Binding - Runtime Verification Guide
/// 
/// This document provides the complete checklist for verifying that FMTC's
/// internal isolate uses the shared HTTP/1.1 IOClient for all tile requests.
///
/// ## Pre-Flight Checks
///
/// 1. **Cache Clear Flag (ONE-TIME)**
///    - File: `lib/map/fmtc_config.dart`
///    - Set: `kClearFMTCOnStartup = true`
///    - Run app ONCE to rebuild cache with correct client
///    - Then set back to `false`
///
/// 2. **Esri URL Format**
///    - File: `lib/map/map_tile_providers.dart`
///    - Verify: `{z}/{y}/{x}` (NOT `{x}/{y}/{z}`)
///    - Current: ✅ Already correct
///
/// 3. **Android Permissions**
///    - File: `android/app/src/main/AndroidManifest.xml`
///    - Verify: `<uses-permission android:name="android.permission.INTERNET" />`
///    - Current: ✅ Already present
///
/// ## Expected Startup Logs (In Order)
///
/// ```
/// [NET] [TileHttpOverrides] Global override active
/// [TileNetworkClient] 🌐 Created HTTP/1.1 client
/// [TileNetworkClient] ⏱️  Connection timeout: 0:00:10.000000
/// [TileNetworkClient] 🏷️  User-Agent: FleetTracker/1.0 (contact@yourdomain.com)
/// [TileNetworkClient] 🔗  maxConnectionsPerHost: 8
/// [TileNetworkClient] ✅ HTTP/1.1 enforced via IOClient wrapper
/// [TileNetworkClient] 📦 gzip compression: true
/// [FMTC][INIT] Store 'main' deleted by config  ← (if kClearFMTCOnStartup = true)
/// [FMTC][INIT] Store 'main' created and ready
/// [FMTC][CLIENT] Shared IOClient will be injected via getTileProvider()
/// [FMTC][CLIENT] HTTP/1.1 enforced, User-Agent: FleetTracker/1.0 (contact@yourdomain.com)
/// [PROBE][OSM] 200 a.tile.openstreetmap.fr
/// [PROBE][Esri] 200 server.arcgisonline.com
/// ```
///
/// ## Map Layer Switch Logs
///
/// When switching between map sources, verify:
///
/// ### OpenStreetMap
/// ```
/// [MAP] Switching to provider: osm (OpenStreetMap)
/// [FMTC][CLIENT] Base layer using shared IOClient for osm
/// ```
///
/// ### Esri Satellite
/// ```
/// [MAP] Switching to provider: esri_sat (Esri Satellite)
/// [FMTC][CLIENT] Base layer using shared IOClient for esri_sat
/// ```
///
/// ### Hybrid Mode
/// ```
/// [MAP] Switching to provider: esri_sat_hybrid (Satellite + Roads)
/// [FMTC][CLIENT] Base layer using shared IOClient for esri_sat_hybrid
/// [FMTC][CLIENT] Overlay layer using shared IOClient
/// ```
///
/// ## Error Logs to Monitor (Should NOT Appear)
///
/// ❌ **These indicate problems:**
/// - `FMTCBrowsingError (unknownFetchException)`
/// - `try specifying a normal HTTP/1.1 IOClient`
/// - `Failed host lookup`
/// - `SocketException`
/// - `HandshakeException`
///
/// ## Offline Cache Test
///
/// 1. Load map and pan around to cache tiles
/// 2. Enable airplane mode or disconnect WiFi
/// 3. Pan within previously viewed area
/// 4. **Expected:** Tiles display instantly from cache (no errors)
///
/// ## Network Probe Validation
///
/// Before FMTC loads tiles, probes test connectivity:
///
/// ### OSM Probe
/// - URL: `https://a.tile.openstreetmap.fr/hot/5/15/12.png`
/// - Expected: `[PROBE][OSM] 200 a.tile.openstreetmap.fr`
/// - If TIMEOUT: Check DNS resolution, VPN, firewall
/// - If ERROR: Verify URL in browser from same device
///
/// ### Esri Probe
/// - URL: `https://server.arcgisonline.com/.../tile/5/15/12`
/// - Expected: `[PROBE][Esri] 200 server.arcgisonline.com`
/// - Headers: Includes `Accept: image/png, image/jpeg, */*`
/// - If TIMEOUT: Check DNS resolution
/// - If 403/401: Verify no auth required for public tiles
///
/// ## Troubleshooting Guide
///
/// ### Issue: Grey Tiles on All Sources
/// **Diagnosis:**
/// - Check for `FMTCBrowsingError` in logs
/// - Verify probes return 200
///
/// **Fix:**
/// 1. Set `kClearFMTCOnStartup = true` (run once)
/// 2. Verify `[FMTC][CLIENT]` logs appear
/// 3. Check DNS: `nslookup server.arcgisonline.com`
///
/// ### Issue: Esri Works in Browser, Fails in App
/// **Diagnosis:**
/// - Browser uses different SSL/TLS stack
/// - App may be using HTTP/2 (FMTC incompatible)
///
/// **Fix:**
/// 1. Verify `[TileNetworkClient] ✅ HTTP/1.1 enforced` log
/// 2. Check `Accept: image/png` header in Esri requests
/// 3. iOS: Add ATS exception for `server.arcgisonline.com`
///
/// ### Issue: Probes Timeout
/// **Diagnosis:**
/// - DNS not resolving
/// - VPN/ad-blocker interference
/// - Firewall blocking tile servers
///
/// **Fix:**
/// 1. Disable VPN temporarily
/// 2. Test URLs in device browser
/// 3. Check device DNS settings
/// 4. Verify WiFi/cellular connectivity
///
/// ### Issue: WebSocket Errors
/// ```
/// SocketException: Failed host lookup: 'your.server'
/// ```
///
/// **Diagnosis:**
/// - Tracking WebSocket trying to connect to placeholder domain
///
/// **Fix:**
/// - Replace `'your.server'` with actual backend domain/IP
/// - Ensure backend is reachable from device
/// - Check backend WebSocket endpoint is running
///
/// ## Success Criteria
///
/// ✅ All startup logs present (see above)
/// ✅ All probes return 200
/// ✅ Zero `FMTCBrowsingError` messages
/// ✅ OSM tiles load instantly
/// ✅ Esri satellite tiles load instantly
/// ✅ Hybrid mode shows satellite + labels
/// ✅ Offline cache works (cached tiles display when offline)
/// ✅ Switching sources is instant (no grey tiles)
///
/// ## iOS-Specific (App Transport Security)
///
/// If you see ATS errors in Xcode console:
///
/// ```xml
/// <!-- Add to ios/Runner/Info.plist -->
/// <key>NSAppTransportSecurity</key>
/// <dict>
///     <key>NSExceptionDomains</key>
///     <dict>
///         <key>server.arcgisonline.com</key>
///         <dict>
///             <key>NSExceptionAllowsInsecureHTTPLoads</key>
///             <false/>
///             <key>NSIncludesSubdomains</key>
///             <true/>
///         </dict>
///     </dict>
/// </dict>
/// ```
///
/// ## Final Verification Commands
///
/// ### Android
/// ```bash
/// # Watch live logs during app run
/// flutter run --verbose
/// ```
///
/// ### Check DNS from device
/// ```bash
/// adb shell ping -c 3 server.arcgisonline.com
/// adb shell ping -c 3 a.tile.openstreetmap.fr
/// ```
///
/// ### Verify INTERNET permission
/// ```bash
/// adb shell dumpsys package com.example.my_app_gps | grep INTERNET
/// ```
///
/// ## Post-Verification Steps
///
/// 1. **Revert cache clear flag:**
///    ```dart
///    // lib/map/fmtc_config.dart
///    static const bool kClearFMTCOnStartup = false;
///    ```
///
/// 2. **Test production build:**
///    ```bash
///    flutter build apk --release
///    flutter install
///    ```
///
/// 3. **Monitor release logs** (no debug symbols):
///    - Should still see User-Agent in network requests
///    - No `badCertificateCallback` active (release-only)
///
/// ---
/// 
/// Last Updated: 2025-10-18
/// FMTC Version: 10.0.0
/// Flutter Map Version: 8.2.2
