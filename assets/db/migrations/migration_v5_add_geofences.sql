-- Migration v5: Add Geofences Table
-- Created: 2025-10-25
-- Purpose: Create geofences table for location-based monitoring with entry/exit/dwell triggers

CREATE TABLE IF NOT EXISTS geofences (
  -- Primary Key
  id TEXT PRIMARY KEY NOT NULL,
  
  -- Owner & Basic Info
  userId TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('circle', 'polygon')),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0, 1)),
  
  -- Circle Geofence Fields (nullable for polygon type)
  centerLat REAL,
  centerLng REAL,
  radius REAL,
  
  -- Polygon Geofence Fields (nullable for circle type)
  -- Stored as JSON array: [{"lat": 33.5, "lng": -7.6}, ...]
  vertices TEXT,
  
  -- Monitored Devices
  -- Stored as JSON array: ["device_001", "device_002", ...]
  monitoredDevices TEXT NOT NULL DEFAULT '[]',
  
  -- Triggers
  onEnter INTEGER NOT NULL DEFAULT 1 CHECK(onEnter IN (0, 1)),
  onExit INTEGER NOT NULL DEFAULT 1 CHECK(onExit IN (0, 1)),
  dwellMs INTEGER,
  
  -- Notification Configuration
  notificationType TEXT NOT NULL DEFAULT 'local' CHECK(notificationType IN ('local', 'push', 'both')),
  
  -- Timestamps (stored as milliseconds since epoch UTC)
  createdAt INTEGER NOT NULL,
  updatedAt INTEGER NOT NULL,
  
  -- Sync Management
  syncStatus TEXT NOT NULL DEFAULT 'synced' CHECK(syncStatus IN ('synced', 'pending', 'conflict')),
  version INTEGER NOT NULL DEFAULT 1
);

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_geofences_user_enabled 
  ON geofences(userId, enabled);

CREATE INDEX IF NOT EXISTS idx_geofences_user_id 
  ON geofences(userId);

CREATE INDEX IF NOT EXISTS idx_geofences_enabled 
  ON geofences(enabled) 
  WHERE enabled = 1;

CREATE INDEX IF NOT EXISTS idx_geofences_sync_status 
  ON geofences(syncStatus) 
  WHERE syncStatus = 'pending';

CREATE INDEX IF NOT EXISTS idx_geofences_updated 
  ON geofences(updatedAt DESC);

-- Validation trigger: Ensure circle has required fields
CREATE TRIGGER IF NOT EXISTS validate_circle_geofence
BEFORE INSERT ON geofences
FOR EACH ROW
WHEN NEW.type = 'circle' AND (NEW.centerLat IS NULL OR NEW.centerLng IS NULL OR NEW.radius IS NULL)
BEGIN
  SELECT RAISE(ABORT, 'Circle geofence must have centerLat, centerLng, and radius');
END;

-- Validation trigger: Ensure polygon has vertices
CREATE TRIGGER IF NOT EXISTS validate_polygon_geofence
BEFORE INSERT ON geofences
FOR EACH ROW
WHEN NEW.type = 'polygon' AND (NEW.vertices IS NULL OR NEW.vertices = '')
BEGIN
  SELECT RAISE(ABORT, 'Polygon geofence must have vertices');
END;

-- Update timestamp trigger
CREATE TRIGGER IF NOT EXISTS update_geofence_timestamp
AFTER UPDATE ON geofences
FOR EACH ROW
BEGIN
  UPDATE geofences 
  SET updatedAt = strftime('%s', 'now') * 1000
  WHERE id = NEW.id;
END;
