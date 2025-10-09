# 📘 Spec - Database (GPS Tracker Flutter App)

## Cloud
- Traccar: Users, devices, positions, trips, geofences, events (authoritative source).

## Local (Drift/SQLite)
Tables (suggested):

- Devices
  - id (PK, Traccar device id)
  - name
  - uniqueId
  - status
  - lastUpdate (DateTime)
  - positionId (nullable)
  - attributes (JSON)
  - updatedAt (DateTime, local cache timestamp)

- Positions
  - id (PK, Traccar position id)
  - deviceId (FK)
  - latitude, longitude
  - speed, course, altitude
  - fixTime (DateTime)
  - valid (bool)
  - attributes (JSON)
  - index: (deviceId, fixTime DESC)

- Trips
  - id (local PK)
  - deviceId (FK)
  - startTime (DateTime)
  - endTime (DateTime)
  - distance (double)
  - cachedPolyline (encoded or GeoJSON)
  - summary (text/json)
  - index: (deviceId, startTime), (deviceId, endTime)

- Events
  - id (PK, Traccar event id if available; else hash)
  - deviceId (FK)
  - type (string)
  - eventTime (DateTime)
  - message (text)
  - priority (int or enum)
  - geofenceId (nullable)
  - attributes (JSON)
  - index: (eventTime DESC), (type)

- Geofences
  - id (PK, Traccar geofence id)
  - name
  - description (nullable)
  - area (GeoJSON or Traccar “area” string)
  - calendarId (nullable)
  - color
  - attributes (JSON)

- DeviceGeofences
  - deviceId (FK)
  - geofenceId (FK)
  - PK: (deviceId, geofenceId)

Indexes:
- Trips: (deviceId, startTime), (deviceId, endTime)
- Events: (eventTime DESC), (type)
- Positions: (deviceId, fixTime DESC)

## Sync Strategy
- Online
  - Devices: GET /api/devices → upsert Devices
  - Positions: via WebSocket “positions” → insert/update Positions and denormalized fields on Devices
  - Trips: GET /api/reports/trips on demand (date range)
  - Events: WebSocket “events” with optional REST backfill
  - Geofences: GET/POST/PUT/DELETE /api/geofences; link via /api/permissions
- Offline
  - Read cached Drift data
  - Show “Offline mode” banner
- Background (Workmanager)
  - Retry pending writes (geofence creates/edits/links) with exponential backoff
  - Refresh devices periodically if socket disconnected

## Serialization
- Use json_serializable/freezed for models
- Store Traccar attributes as JSON blobs
- Convert map shapes to/from Traccar area format or GeoJSON abstraction in app