# 📘 Spec - APIs (GPS Tracker Flutter App with Traccar)

Base URL
- TRACCAR_BASE_URL (e.g., https://traccar.example.com)

## Authentication
- Endpoint: POST /api/session
- Request body: { "email": "user@example.com", "password": "secret" }
- Response: User object; Set-Cookie: JSESSIONID
- Client:
  - Use Dio + dio_cookie_manager to persist JSESSIONID.
  - Include CookieJar in WebSocket handshake to authorize /api/socket.
- Alternative (optional): Permanent access token
  - Header: Authorization: Bearer <token>
  - Configure token in Traccar (UI or API). Prefer HTTPS.

Notes:
- Logout: DELETE /api/session clears server-side session.
- For Web builds, ensure CORS on Traccar or use a reverse proxy.

## Devices
- Endpoint: GET /api/devices
- Response: List of devices (id, name, uniqueId, status, lastUpdate, positionId, attributes)
- Notes:
  - Device.status: "online" | "offline" | "unknown"
  - positionId can be used to GET /api/positions/{id} for latest position details if needed.

## Positions
- Historical positions: GET /api/positions?deviceId={id}&from={iso8601}&to={iso8601}
- Latest position:
  - Option A: Use device.positionId and GET /api/positions/{positionId}
  - Option B: Listen to WebSocket “positions” messages

## Trips
- Endpoint: GET /api/reports/trips?deviceId={id}&from={iso8601}&to={iso8601}
- Response: Trip segments with start/end times, distance, and coordinates (array)

## Events (Notifications)
- Realtime: WebSocket stream message type “events”
- REST: GET /api/reports/events?deviceId={id}&from={iso8601}&to={iso8601}&type={optional}
- Common event types: deviceOnline, deviceOffline, overspeed, geofenceEnter, geofenceExit, ignitionOn, ignitionOff
- App priority mapping:
  - High: overspeed, ignitionOff while moving (if derived)
  - Medium: geofenceEnter/Exit
  - Low/Info: deviceOnline/Offline

## Geofences
- CRUD: GET/POST/PUT/DELETE /api/geofences
- Link to device: POST /api/permissions
  - Body: { "deviceId": <id>, "geofenceId": <id> }
- Unlink: DELETE /api/permissions?deviceId={id}&geofenceId={id}

## Commands
- Send: POST /api/commands/send
- Body: { "deviceId": <id>, "type": "engineStop" | "engineResume" | ... , "attributes": { ... } }
- Notes: Actual support depends on device protocol; surface errors to UI.

## Real-time Updates (WebSocket)
- URL: {TRACCAR_BASE_URL} replacing http→ws or https→wss, path /api/socket
  - Example: wss://traccar.example.com/api/socket
- Auth: session cookie (JSESSIONID) or token (query or header if supported)
- Messages:
  - positions: { "positions": [ {deviceId, latitude, longitude, speed, course, attributes, deviceTime, serverTime} ] }
  - events: { "events": [ {type, deviceId, geofenceId?, attributes, eventTime} ] }
  - devices: { "devices": [ {id, status, lastUpdate, ...} ] } (on change)
- Client: Reconnect with backoff; debounce UI updates; push to Riverpod streams.

## Error Handling
- 401/403: Expired session or invalid token → prompt re-login.
- 5xx: Show SnackBar; fallback to cached data.
- Rate limits: Use sensible polling fallback intervals when socket unavailable.

## Time and Formats
- Use ISO 8601 UTC for from/to parameters (e.g., 2025-09-30T00:00:00Z).
- Display with local timezone using intl.