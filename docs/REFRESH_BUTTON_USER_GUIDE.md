# Refresh Button - User Guide

## Location
The refresh button is located in the top-right corner of the map screen, below the connection status indicator.

## Visual States

### 1. Normal State (Ready to Refresh)
```
┌─────────────────────────┐
│  🟢 Connected  2 devices│
│                         │
│    [🔄]  ← Tap here    │
│                         │
│    [🎯]                │
└─────────────────────────┘
```
- White circular button with refresh icon
- Shadow/elevation for depth
- Tappable

### 2. Loading State (Refreshing...)
```
┌─────────────────────────┐
│  🟢 Connected  2 devices│
│                         │
│    [⊙]  ← Spinning     │
│                         │
│    [🎯]                │
└─────────────────────────┘
```
- Circular progress spinner replaces icon
- Button is disabled (no tap)
- Spinner animates continuously

### 3. Success (After Refresh)
```
┌─────────────────────────────────────┐
│ ✅ Data refreshed successfully      │
└─────────────────────────────────────┘
      ↑ Green snackbar at bottom
```
- Button returns to normal state
- Green success message appears for 2 seconds
- Markers and info updated on map

### 4. Error (If Refresh Fails)
```
┌─────────────────────────────────────┐
│ ❌ Refresh failed: Network error    │
└─────────────────────────────────────┘
      ↑ Red snackbar at bottom
```
- Button returns to normal state
- Red error message appears for 3 seconds
- Shows specific error reason

## What Gets Refreshed

When you tap the refresh button:

1. **Device List** 
   - Latest device information from Traccar
   - Device names, statuses, attributes

2. **Position Data**
   - Current locations for all vehicles
   - Speed, engine status, distance traveled
   - Coordinates and heading

3. **Map Markers**
   - Marker positions update immediately
   - Colors reflect latest status (online/offline)
   - Engine indicators (green = on, gray = off)

4. **Info Cards**
   - Bottom panel shows fresh data
   - Speed, distance, location updated
   - Engine status reflects current state

## Usage Tips

### When to Refresh
- Vehicle markers seem outdated
- After switching back from another app
- Network reconnects after being offline
- Position data doesn't match Traccar web panel

### What to Expect
- **Duration**: 1-3 seconds typically
- **Visual**: Spinner shows progress
- **Feedback**: Success/error message confirms
- **Updates**: Markers move to new positions instantly

### Troubleshooting

**Spinner keeps spinning?**
- Check network connection
- Verify Traccar server is online
- Wait up to 10 seconds for slow connections

**No changes after refresh?**
- Vehicles might be stationary
- Check if WebSocket is connected (green badge)
- Try again after a few seconds

**Error message appears?**
- "Network error" → Check internet connection
- "Server error" → Traccar backend might be down
- "Timeout" → Slow network, try again

## Keyboard Shortcut
Currently: None
Future: Consider Ctrl+R or F5 for desktop

## Related Features
- **WebSocket Connection**: Real-time updates happen automatically
- **Auto-Refresh**: Background updates every 45 seconds
- **Manual Focus**: Tap device marker to center and refresh its data

## Technical Notes
- Prevents double-taps during refresh
- Maintains UI responsiveness
- Handles offline scenarios gracefully
- Position updates trigger marker re-render
- Repository caching ensures fast subsequent loads
