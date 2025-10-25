-- Migration v5: Add Geofence Events Table
-- Created: 2025-10-25
-- Purpose: Create geofence_events table to track device entry/exit/dwell events

CREATE TABLE IF NOT EXISTS geofence_events (
  -- Primary Key
  id TEXT PRIMARY KEY NOT NULL,
  
  -- References
  geofenceId TEXT NOT NULL,
  geofenceName TEXT NOT NULL,
  deviceId TEXT NOT NULL,
  deviceName TEXT NOT NULL,
  
  -- Event Details
  eventType TEXT NOT NULL CHECK(eventType IN ('enter', 'exit', 'dwell')),
  timestamp INTEGER NOT NULL,
  
  -- Location Data
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  
  -- Dwell-specific field (nullable for enter/exit)
  dwellDurationMs INTEGER,
  
  -- Event Status
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'acknowledged', 'archived')),
  
  -- Sync Management
  syncStatus TEXT NOT NULL DEFAULT 'synced' CHECK(syncStatus IN ('synced', 'pending')),
  
  -- Audit Trail
  createdAt INTEGER NOT NULL,
  
  -- Optional: additional metadata as JSON
  attributesJson TEXT DEFAULT '{}',
  
  -- Foreign Key Constraint
  FOREIGN KEY (geofenceId) REFERENCES geofences(id) ON DELETE CASCADE
);

-- Indexes for fast queries

-- Query events by geofence (most common use case)
CREATE INDEX IF NOT EXISTS idx_events_geo_ts 
  ON geofence_events(geofenceId, timestamp DESC);

-- Query events by device
CREATE INDEX IF NOT EXISTS idx_events_dev_ts 
  ON geofence_events(deviceId, timestamp DESC);

-- Query recent events
CREATE INDEX IF NOT EXISTS idx_events_timestamp 
  ON geofence_events(timestamp DESC);

-- Query unread events
CREATE INDEX IF NOT EXISTS idx_events_status 
  ON geofence_events(status) 
  WHERE status = 'pending';

-- Query events needing sync
CREATE INDEX IF NOT EXISTS idx_events_sync_status 
  ON geofence_events(syncStatus) 
  WHERE syncStatus = 'pending';

-- Composite index for device + event type queries
CREATE INDEX IF NOT EXISTS idx_events_dev_type_ts 
  ON geofence_events(deviceId, eventType, timestamp DESC);

-- Composite index for geofence + event type queries
CREATE INDEX IF NOT EXISTS idx_events_geo_type_ts 
  ON geofence_events(geofenceId, eventType, timestamp DESC);

-- Auto-cleanup trigger: Delete old archived events (optional, can be disabled)
-- Keeps last 90 days of archived events
CREATE TRIGGER IF NOT EXISTS cleanup_old_archived_events
AFTER INSERT ON geofence_events
FOR EACH ROW
WHEN NEW.status = 'archived'
BEGIN
  DELETE FROM geofence_events
  WHERE status = 'archived'
    AND timestamp < (strftime('%s', 'now') - 7776000) * 1000  -- 90 days in seconds
    AND id != NEW.id;
END;

-- Validation trigger: Ensure dwell events have duration
CREATE TRIGGER IF NOT EXISTS validate_dwell_duration
BEFORE INSERT ON geofence_events
FOR EACH ROW
WHEN NEW.eventType = 'dwell' AND NEW.dwellDurationMs IS NULL
BEGIN
  SELECT RAISE(ABORT, 'Dwell events must have dwellDurationMs');
END;
