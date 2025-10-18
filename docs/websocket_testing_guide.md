# WebSocket Manager - Testing Guide

## 🧪 Manual Testing Procedures

This guide helps you verify the WebSocket refactor works correctly.

---

## Prerequisites

1. **Device/Emulator:** Android or iOS device with network toggle capability
2. **Server:** WebSocket server running (or use placeholder behavior)
3. **Logs:** Enable debug logs to see WebSocket state transitions

---

## Test 1: Normal Startup (Online)

### Steps:
1. Ensure device has network connectivity (Wi-Fi or mobile data)
2. Close and restart the app
3. Watch the logs for WebSocket initialization

### Expected Logs:
```
[WS][INIT] Connecting...
[WS] 🔗 Socket opened, awaiting confirmation...
[WS] ✅ Connection confirmed (first message received)
[WS][PONG] latency: XXms
```

### ✅ Pass Criteria:
- Single `✅ Connection confirmed` log (no duplicates)
- Pong responses showing healthy connection
- No error messages

### ❌ Fail Indicators:
- Multiple "Connection confirmed" logs → Debouncing not working
- Immediate error after "Socket opened" → Server issue
- No confirmation within 10s → Connection timeout

---

## Test 2: Startup While Offline

### Steps:
1. Enable airplane mode or disable all network connections
2. Launch the app
3. Watch for connection attempts and pause behavior

### Expected Logs:
```
[WS][INIT] Connecting...
[WS] ❌ SocketException: Network is unreachable
[WS] 🔄 Retry attempt #1 in 1s (exponential backoff)
[CONNECTIVITY_PROVIDER] 🔴 OFFLINE detected
[WS] ⏸️ PAUSED (offline detected) - stopping retries
```

### ✅ Pass Criteria:
- Initial connection attempt fails (expected)
- Connectivity provider detects offline state
- WebSocket pauses and stops retry spam
- No further retry logs after pause

### ❌ Fail Indicators:
- Continuous retry attempts every 2s → Pause not working
- No "PAUSED" log → Integration not working
- App crash on connection error → Exception handling broken

---

## Test 3: Exponential Backoff (Server Down)

### Steps:
1. Ensure network is online but WebSocket server is stopped/unreachable
2. Launch the app or force reconnect
3. Observe retry timing

### Expected Logs:
```
[WS][INIT] Connecting...
[WS] ❌ WebSocketException: Connection refused
[WS] 🔄 Retry attempt #1 in 1s (exponential backoff)
[WS][INIT] Connecting...
[WS] ❌ WebSocketException: Connection refused
[WS] 🔄 Retry attempt #2 in 2s (exponential backoff)
[WS][INIT] Connecting...
[WS] ❌ WebSocketException: Connection refused
[WS] 🔄 Retry attempt #3 in 4s (exponential backoff)
[WS][INIT] Connecting...
[WS] ❌ WebSocketException: Connection refused
[WS] 🔄 Retry attempt #4 in 8s (exponential backoff)
[WS][INIT] Connecting...
[WS] ❌ WebSocketException: Connection refused
[WS] 🔄 Retry attempt #5 in 16s (exponential backoff)
```

### ✅ Pass Criteria:
- Retry delays double each attempt: 1s, 2s, 4s, 8s, 16s, 32s, 60s
- After attempt #6, all retries use 60s (max cap)
- No retry spam at 2s intervals

### ❌ Fail Indicators:
- All retries at 2s intervals → Exponential backoff not implemented
- Retries exceed 60s → Max cap not working
- No retry logs → Retry logic broken

---

## Test 4: Offline → Online Transition

### Steps:
1. Start app while online (connected state)
2. Enable airplane mode
3. Wait for pause logs
4. Disable airplane mode (restore connectivity)
5. Observe resume behavior

### Expected Logs:
```
// Initial connection
[WS] ✅ Connection confirmed (first message received)
[WS][PONG] latency: 42ms

// Go offline
[CONNECTIVITY_PROVIDER] 🔴 OFFLINE detected
[WS] ⏸️ PAUSED (offline detected) - stopping retries
[WS][CLOSE] Connection closed gracefully

// Back online
[CONNECTIVITY_PROVIDER] 🟢 RECONNECTED after 42s
[WS] ▶️ RESUMED (network restored) - attempting reconnection
[WS][INIT] Connecting...
[WS] 🔗 Socket opened, awaiting confirmation...
[WS] ✅ Connection confirmed (first message received)
```

### ✅ Pass Criteria:
- Clean pause on offline transition
- Automatic resume when back online
- Single confirmation after resume
- Retry count reset to 0 on resume

### ❌ Fail Indicators:
- No resume after coming online → Resume not triggered
- Multiple "Connection confirmed" logs → Debouncing broken
- Retries continue during offline period → Pause not working

---

## Test 5: Circuit Breaker

### Steps:
1. Ensure server is down/unreachable
2. Let app retry 10+ times
3. Observe circuit breaker behavior

### Expected Logs:
```
[WS] 🔄 Retry attempt #10 in 60s (exponential backoff)
[WS][INIT] Connecting...
[WS] ❌ SocketException: Connection timeout
[WS][CIRCUIT BREAKER] ⛔ Too many retries (10), pausing for 2m

... (wait 2 minutes) ...

[WS][CIRCUIT BREAKER] 🔓 Circuit breaker reset, resuming
[WS][INIT] Connecting...
```

### ✅ Pass Criteria:
- Circuit breaker triggers after 10 failed attempts
- No retries for 2 minutes after circuit breaker
- Automatic resume after 2 minutes
- Retry count resets after circuit breaker

### ❌ Fail Indicators:
- Retries continue indefinitely → Circuit breaker not working
- Circuit breaker never resets → Timer not working

---

## Test 6: Connection Stability (Ping/Pong)

### Steps:
1. Connect to WebSocket server
2. Let connection run for 2+ minutes
3. Observe ping/pong heartbeats

### Expected Logs:
```
[WS] ✅ Connection confirmed (first message received)
[WS][PONG] latency: 42ms
... (30s later) ...
[WS][PONG] latency: 38ms
... (30s later) ...
[WS][PONG] latency: 51ms
```

### ✅ Pass Criteria:
- Pong responses every ~30 seconds
- Latency typically < 100ms for local network
- No disconnections or reconnects

### ❌ Fail Indicators:
- `[WS][PONG TIMEOUT]` → Connection unstable
- No pong responses → Ping not working
- Frequent reconnects → Server issues

---

## Test 7: Error Recovery (Temporary Network Drop)

### Steps:
1. Start with stable connection
2. Briefly turn off Wi-Fi (2-3 seconds)
3. Turn Wi-Fi back on immediately
4. Observe recovery behavior

### Expected Logs:
```
// Before drop
[WS][PONG] latency: 42ms

// During drop
[WS][ERROR] Stream error: SocketException - Connection lost
[CONNECTIVITY_PROVIDER] 🔴 OFFLINE detected
[WS] ⏸️ PAUSED (offline detected) - stopping retries

// After recovery
[CONNECTIVITY_PROVIDER] 🟢 RECONNECTED after 3s
[WS] ▶️ RESUMED (network restored) - attempting reconnection
[WS][INIT] Connecting...
[WS] ✅ Connection confirmed (first message received)
```

### ✅ Pass Criteria:
- Clean error handling (no crashes)
- Quick pause on offline detection
- Automatic resume and reconnect
- Connection restored within a few seconds

### ❌ Fail Indicators:
- App crash → Exception not caught
- Long reconnect delay → Resume not working
- Multiple confirmation logs → Debouncing broken

---

## Test 8: Invalid Server URL (Placeholder Check)

### Steps:
1. Ensure `_wsUrl` contains `'your.server'` (default placeholder)
2. Launch app
3. Verify circuit breaker prevents retries

### Expected Logs:
```
[WS] ⚠️ Invalid hostname: "your.server" - skipping connection
[WS] 💡 Update _wsUrl in websocket_manager.dart with actual server URL
```

### ✅ Pass Criteria:
- No connection attempts
- Clear error message about placeholder URL
- No retry spam
- Circuit breaker open

### ❌ Fail Indicators:
- Connection attempts despite placeholder → Validation broken
- Retry spam → Circuit breaker not triggered

---

## 📊 Test Result Template

Copy and use this template to track test results:

```
# WebSocket Refactor Test Results

**Date:** _____________
**Tester:** _____________
**Device:** _____________
**OS Version:** _____________

## Test Results

| Test # | Test Name | Pass/Fail | Notes |
|--------|-----------|-----------|-------|
| 1 | Normal Startup (Online) | ☐ Pass ☐ Fail | |
| 2 | Startup While Offline | ☐ Pass ☐ Fail | |
| 3 | Exponential Backoff | ☐ Pass ☐ Fail | |
| 4 | Offline → Online Transition | ☐ Pass ☐ Fail | |
| 5 | Circuit Breaker | ☐ Pass ☐ Fail | |
| 6 | Connection Stability | ☐ Pass ☐ Fail | |
| 7 | Error Recovery | ☐ Pass ☐ Fail | |
| 8 | Invalid Server URL | ☐ Pass ☐ Fail | |

## Issues Found

1. _____________________________________________
2. _____________________________________________
3. _____________________________________________

## Overall Status

☐ All tests passed - ready for production
☐ Minor issues - acceptable with notes
☐ Major issues - requires fixes
```

---

## 🛠️ Troubleshooting

### Issue: No logs appearing

**Solution:**
- Ensure debug mode is enabled
- Check if `kDebugMode` is true
- Verify `debugPrint` output is visible in your IDE

### Issue: Pause not working

**Solution:**
- Verify ConnectivityProvider is initialized
- Check that `_onOffline()` calls `pause()`
- Ensure `_isPaused` flag is set correctly

### Issue: Resume not working

**Solution:**
- Verify ConnectivityProvider detects online state
- Check that `_onReconnect()` calls `resume()`
- Ensure `_isPaused` is cleared on resume

### Issue: Exponential backoff shows wrong delays

**Solution:**
- Check retry count increments correctly
- Verify formula: `(1 << (_retryCount - 1)).clamp(1, 60)`
- Confirm `_maxRetryDelay` is 60 seconds

### Issue: Duplicate "Connection confirmed"

**Solution:**
- Verify `_isFullyConnected` flag is used
- Check flag is reset on new connection
- Ensure flag is set only once in `_listen()`

---

## 📝 Log Collection

For bug reports, collect logs showing:

1. **Timestamp:** When issue occurred
2. **Initial state:** Connection status before issue
3. **Trigger:** What caused the issue (offline, server down, etc.)
4. **Response:** What logs appeared after trigger
5. **Duration:** How long until recovery (if applicable)

### Example:
```
2025-10-18 14:23:05 [WS] ✅ Connection confirmed (first message received)
2025-10-18 14:23:35 [WS][PONG] latency: 42ms
2025-10-18 14:24:05 [WS][PONG] latency: 38ms
2025-10-18 14:24:12 [USER ACTION] Enabled airplane mode
2025-10-18 14:24:13 [WS][ERROR] Stream error: SocketException
2025-10-18 14:24:13 [CONNECTIVITY_PROVIDER] 🔴 OFFLINE detected
2025-10-18 14:24:13 [WS] ⏸️ PAUSED (offline detected)
2025-10-18 14:24:30 [USER ACTION] Disabled airplane mode
2025-10-18 14:24:32 [CONNECTIVITY_PROVIDER] 🟢 RECONNECTED
2025-10-18 14:24:32 [WS] ▶️ RESUMED (network restored)
2025-10-18 14:24:33 [WS][INIT] Connecting...
2025-10-18 14:24:34 [WS] 🔗 Socket opened, awaiting confirmation...
2025-10-18 14:24:34 [WS] ✅ Connection confirmed
```

---

## ✅ Acceptance Criteria

All tests must pass before merging to production:

- [ ] Test 1: Normal startup succeeds with single confirmation
- [ ] Test 2: Offline startup pauses retries
- [ ] Test 3: Exponential backoff follows 1s → 2s → 4s → ... → 60s
- [ ] Test 4: Offline/online transitions work cleanly
- [ ] Test 5: Circuit breaker triggers after max retries
- [ ] Test 6: Ping/pong heartbeats maintain connection
- [ ] Test 7: Temporary network drops recover automatically
- [ ] Test 8: Invalid URL doesn't cause retry spam

---

## 🚀 Next Steps After Testing

1. **If all tests pass:**
   - Update WebSocket URL to production server
   - Deploy to staging environment
   - Monitor logs for 24-48 hours
   - Roll out to production

2. **If any test fails:**
   - Document the failure with logs
   - Create a bug report with test number and logs
   - Fix the issue
   - Rerun all tests

3. **Production monitoring:**
   - Track retry frequency
   - Monitor circuit breaker triggers
   - Check average connection latency
   - Alert on unusual patterns
