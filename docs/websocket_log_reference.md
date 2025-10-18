# WebSocket Manager - Log Reference Card

Quick reference for understanding WebSocket manager debug logs.

## 🔍 Log Patterns

### Connection States

| Log | Meaning | Action Required |
|-----|---------|-----------------|
| `🔗 Socket opened, awaiting confirmation...` | Socket connected, waiting for first message | Normal - wait for confirmation |
| `✅ Connection confirmed (first message received)` | WebSocket fully operational | ✅ All good |
| `⏸️ PAUSED (offline detected) - stopping retries` | Device went offline, retries stopped | Normal offline behavior |
| `▶️ RESUMED (network restored) - attempting reconnection` | Device back online, reconnecting | Normal recovery |
| `⛔ Too many retries (N), pausing for 2m` | Circuit breaker triggered | Check server availability |

### Errors

| Log | Meaning | Likely Cause |
|-----|---------|--------------|
| `❌ SocketException: Network is unreachable` | No network connectivity | Device offline or no route to server |
| `❌ WebSocketException: ...` | WebSocket protocol error | Server not accepting WS connections |
| `❌ Timeout: WebSocket connection timeout` | Connection took >10s | Server slow or unreachable |
| `❌ Connection error: ...` | Generic connection failure | Check server URL and firewall |
| `⚠️ Failed to parse message: ...` | Invalid JSON received | Server sending malformed data |

### Retry Behavior

| Log | Meaning | Next Retry |
|-----|---------|-----------|
| `🔄 Retry attempt #1 in 1s (exponential backoff)` | First retry | 1 second |
| `🔄 Retry attempt #2 in 2s (exponential backoff)` | Second retry | 2 seconds |
| `🔄 Retry attempt #3 in 4s (exponential backoff)` | Third retry | 4 seconds |
| `🔄 Retry attempt #4 in 8s (exponential backoff)` | Fourth retry | 8 seconds |
| `🔄 Retry attempt #5 in 16s (exponential backoff)` | Fifth retry | 16 seconds |
| `🔄 Retry attempt #6 in 32s (exponential backoff)` | Sixth retry | 32 seconds |
| `🔄 Retry attempt #7+ in 60s (exponential backoff)` | Max backoff reached | 60 seconds (max) |

### Health Checks

| Log | Meaning | Status |
|-----|---------|--------|
| `[WS][PONG] latency: XXms` | Ping/pong successful | ✅ Connection healthy |
| `[WS][PONG TIMEOUT] Reconnecting...` | No pong response in 15s | ⚠️ Connection lost |
| `[WS][CLOSE] Connection closed gracefully` | Server closed connection | Normal - will retry |

## 🎯 Common Scenarios

### Scenario 1: App Starts While Online
```
[WS][INIT] Connecting...
[WS] 🔗 Socket opened, awaiting confirmation...
[WS] ✅ Connection confirmed (first message received)
[WS][PONG] latency: 45ms
```
**Status:** ✅ All good

---

### Scenario 2: App Starts While Offline
```
[WS][INIT] Connecting...
[WS] ❌ SocketException: Network is unreachable
[WS] 🔄 Retry attempt #1 in 1s (exponential backoff)
[CONNECTIVITY_PROVIDER] 🔴 OFFLINE detected
[WS] ⏸️ PAUSED (offline detected) - stopping retries
```
**Status:** ⏸️ Paused - waiting for network

---

### Scenario 3: Device Goes Offline While Connected
```
[WS][ERROR] Stream error: SocketException - Connection lost
[CONNECTIVITY_PROVIDER] 🔴 OFFLINE detected
[WS] ⏸️ PAUSED (offline detected) - stopping retries
[WS][CLOSE] Connection closed gracefully
```
**Status:** ⏸️ Paused - will resume when back online

---

### Scenario 4: Device Comes Back Online
```
[CONNECTIVITY_PROVIDER] 🟢 RECONNECTED after 42s
[WS] ▶️ RESUMED (network restored) - attempting reconnection
[WS][INIT] Connecting...
[WS] 🔗 Socket opened, awaiting confirmation...
[WS] ✅ Connection confirmed (first message received)
```
**Status:** ✅ Reconnected successfully

---

### Scenario 5: Server Down (Exponential Backoff)
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
... (continues with 8s, 16s, 32s, 60s intervals)
```
**Status:** 🔄 Retrying with exponential backoff

---

### Scenario 6: Circuit Breaker Triggered
```
[WS] 🔄 Retry attempt #10 in 60s (exponential backoff)
[WS][INIT] Connecting...
[WS] ❌ SocketException: Connection timeout
[WS][CIRCUIT BREAKER] ⛔ Too many retries (10), pausing for 2m
... (waits 2 minutes) ...
[WS][CIRCUIT BREAKER] 🔓 Circuit breaker reset, resuming
[WS][INIT] Connecting...
```
**Status:** ⛔ Circuit breaker - will retry after timeout

---

## 🚨 Red Flags

These logs indicate issues that need attention:

| Log Pattern | Problem | Fix |
|-------------|---------|-----|
| Repeated `❌ WebSocketException: Connection refused` | Server not running | Start WebSocket server |
| Repeated `❌ Timeout: ...` | Server too slow | Check server performance |
| `⚠️ Invalid hostname: "your.server"` | URL not configured | Update `_wsUrl` in `websocket_manager.dart` |
| Circuit breaker triggers repeatedly | Server unstable | Investigate server logs |
| `⚠️ Failed to parse message: ...` | Invalid JSON from server | Fix server response format |

---

## ✅ Healthy Patterns

These log patterns indicate normal operation:

1. **Single connection confirmation:**
   ```
   🔗 Socket opened, awaiting confirmation...
   ✅ Connection confirmed (first message received)
   ```

2. **Regular heartbeats:**
   ```
   [WS][PONG] latency: 42ms
   [WS][PONG] latency: 38ms
   [WS][PONG] latency: 51ms
   ```

3. **Clean offline/online transitions:**
   ```
   🔴 OFFLINE detected → ⏸️ PAUSED
   🟢 RECONNECTED → ▶️ RESUMED → ✅ Connection confirmed
   ```

4. **Exponential backoff on temporary failures:**
   ```
   🔄 Retry #1 in 1s
   🔄 Retry #2 in 2s
   ✅ Connection confirmed  ← Success!
   ```

---

## 🛠️ Debugging Tips

### Check Connection Status
Look for the most recent status log:
- `✅ Connection confirmed` = Connected
- `⏸️ PAUSED` = Offline mode
- `🔄 Retry attempt #N` = Retrying
- `⛔ Circuit breaker` = Paused due to repeated failures

### Measure Connection Quality
Check pong latency:
- `< 100ms` = Excellent
- `100-300ms` = Good
- `300-1000ms` = Acceptable
- `> 1000ms` or timeout = Poor connection

### Identify Retry Frequency
Count retry attempts to see backoff progression:
- Attempts 1-3: Should retry quickly (1-4s)
- Attempts 4-6: Should slow down (8-32s)
- Attempts 7+: Should max out at 60s

### Check for Duplicate "Connection Confirmed"
✅ **Good:** Single confirmation per connection
```
🔗 Socket opened...
✅ Connection confirmed
```

❌ **Bad (old behavior):** Multiple confirmations
```
✅ Connected
✅ Connected
✅ Connected
```

If you see the bad pattern, the debouncing isn't working.

---

## 📞 Support

If you see unexpected behavior:

1. **Check WebSocket URL:** Ensure `_wsUrl` is correct
2. **Verify server is running:** Test with `wscat` or browser
3. **Check firewall rules:** Ensure WebSocket port is open
4. **Review server logs:** Check for rejected connections
5. **Test connectivity:** Toggle airplane mode to verify pause/resume

For persistent issues, collect logs showing:
- Initial connection attempt
- At least 3 retry attempts
- Offline/online transition
- Any error messages
