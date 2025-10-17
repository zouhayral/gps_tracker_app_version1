# GPS Tracker Marker Design Specification

## Overview
This document provides the complete design specification for GPS tracker map markers across all device states. The markers use a modern, clean design with clear visual indicators for connection status, ignition state, and movement.

## Design Philosophy
- **Circular/Pin Shape**: Location pin for stopped vehicles, compact circles for moving vehicles
- **Color-Coded States**: Immediate visual feedback through color
- **Status Indicators**: Small overlay icons for ignition and connection status
- **Motion Trails**: Dots indicating movement direction and speed
- **App Color Integration**: Uses app seed color (#A6CD27) for active states

---

## Marker States

### State 1: Online + Ignition ON + Stopped
**Condition**: Device is connected, engine is running, but vehicle is not moving

#### Visual Design
- **Main Shape**: Location pin/teardrop shape
- **Primary Color**: `#A6CD27` (Light Green - App Seed Color)
- **Icon**: White car icon (front view)
- **Border**: White circular border around car icon
- **Size**: Larger (approx. 56x56 base + pin tail)

#### Status Indicators
- **Ignition Indicator (Power Icon)**:
  - Position: Top-left corner
  - Style: Small circular badge showing a power symbol (⏻) in white
  - Color: Green (#A6CD27) when ignition ON; Red (#FF383C) when OFF; Grey (#9E9E9E) NEUTRAL when device is disconnected
  - Size: ~16px diameter

#### Use Case
- Vehicle is parked with engine idling
- Delivery truck stopped at location with engine on
- Vehicle at traffic light

#### Implementation Notes
```dart
// State conditions
online: true
engineOn: true  
moving: false
speed: 0 or < 1 km/h
```

---

### State 2: Online + Ignition ON + Moving
**Condition**: Device is connected, engine is running, and vehicle is in motion

#### Visual Design
- **Main Shape**: Compact circle
- **Primary Color**: `#A6CD27` (Light Green - App Seed Color)
- **Icon**: White circular rotation/movement symbol (⟳)
- **Border**: White circular border
- **Size**: Standard (approx. 48x48)

#### Status Indicators
- **Ignition Indicator (Power Icon)**:
  - Position: Top-left corner
  - Style: Small circular badge with power icon (⏻)
  - Color rules: Green when ON; Red when OFF; Grey when device disconnected
  - Size: ~14px diameter

- **Motion Trail**:
  - Position: Bottom-right (trailing)
  - Style: Three small dots
  - Color: Green (#A6CD27)
  - Size: ~4px diameter per dot
  - Spacing: Decreasing from marker

#### Use Case
- Vehicle actively driving
- In-transit delivery
- Route navigation active

#### Implementation Notes
```dart
// State conditions
online: true
engineOn: true
moving: true
speed: >= 1 km/h
```

---

### State 3: Online + Ignition OFF + Stopped
**Condition**: Device is connected, engine is off, vehicle is not moving

#### Visual Design
- **Main Shape**: Compact circle
- **Primary Color**: `#A6CD27` (Light Green - App Seed Color)
- **Icon**: White circular rotation symbol (⟳)
- **Border**: White circular border
- **Size**: Standard (approx. 48x48)

#### Status Indicators
- **Ignition Indicator (Power Icon)**:
  - Position: Top-left corner
  - Style: Small circular badge with power icon (⏻)
  - Color: Red (#FF383C) for ignition OFF; Grey (#9E9E9E) if disconnected
  - Size: ~14px diameter

- **Status Dot**:
  - Position: Bottom center
  - Style: Single small dot
  - Color: Green (#A6CD27)
  - Size: ~4px diameter

#### Use Case
- Parked vehicle with engine off
- Completed delivery stop
- Overnight parking

#### Implementation Notes
```dart
// State conditions
online: true
engineOn: false
moving: false
speed: 0
```

---

### State 4: Offline/Disconnected + Any Ignition State
**Condition**: Device has lost connection to server

#### Visual Design
- **Main Shape**: Compact circle
- **Primary Color**: `#9E9E9E` (Grey - Offline Color)
- **Icon**: White circular rotation symbol (⟳)
- **Border**: White circular border
- **Size**: Standard (approx. 48x48)

#### Status Indicators
- **Ignition Indicator (Power Icon, NEUTRAL)**:
  - Position: Top-left corner
  - Style: Small circular badge with power icon (⏻)
  - Color: Grey (#9E9E9E) to indicate NEUTRAL when the device is disconnected
  - Size: ~14px diameter

- **Status Dot**:
  - Position: Bottom center
  - Style: Single small dot
  - Color: Grey (#9E9E9E)
  - Size: ~4px diameter

#### Use Case
- Lost cellular connection
- Device powered off
- GPS signal lost
- Last known position

#### Implementation Notes
```dart
// State conditions
online: false
engineOn: any
moving: false (last known state)
```

---

### State 5: Offline + Ignition OFF (Warning State)
**Condition**: Device is offline AND ignition is confirmed off (last known state)

#### Visual Design
- **Main Shape**: Compact circle
- **Primary Color**: `#FFC107` (Yellow/Amber - Warning Color)
- **Icon**: White circular rotation symbol (⟳)
- **Border**: White circular border
- **Size**: Standard (approx. 48x48)

#### Status Indicators
- **Ignition Indicator (Power Icon, NEUTRAL/OFF)**:
  - Position: Top-left corner
  - Style: Small circular badge with power icon (⏻)
  - Color: Grey (#9E9E9E) when disconnected; Red (#FF383C) if ignition OFF was last known
  - Size: ~14px diameter

- **Status Dot**:
  - Position: Bottom center
  - Style: Single small dot
  - Color: Yellow/Amber (#FFC107)
  - Size: ~4px diameter

#### Use Case
- Parked vehicle that lost connection
- Battery died while parked
- Potential theft scenario (engine off but disconnected)
- Maintenance mode

#### Implementation Notes
```dart
// State conditions
online: false
engineOn: false (last known)
moving: false (last known)
```

---

## Color Palette

### Primary Colors
| Color Name | Hex Code | RGB | Usage |
|------------|----------|-----|-------|
| App Green (Seed) | `#A6CD27` | rgb(166, 205, 39) | Online, moving, active states |
| Neutral Grey | `#49454F` | rgb(73, 69, 79) | Neutral elements, borders |
| Danger Red | `#FF383C` | rgb(255, 56, 60) | Alerts, ignition off, offline |
| Offline Grey | `#9E9E9E` | rgb(158, 158, 158) | Disconnected devices |
| Warning Amber | `#FFC107` | rgb(255, 193, 7) | Offline + ignition off |
| Ignition Orange | `#FF9800` | rgb(255, 152, 0) | Ignition on indicator (moving) |
| White | `#FFFFFF` | rgb(255, 255, 255) | Icons, borders, text |

### Indicator Colors
- **Online**: Green (#A6CD27)
- **Offline**: Grey (#9E9E9E) or Amber (#FFC107)
- **Ignition On**: Green (#A6CD27)
- **Ignition Off**: Red (#FF383C)
- **Disconnected (Ignition Neutral)**: Grey (#9E9E9E)

---

## Size Specifications

### Marker Dimensions
- **Large (Stopped/Selected)**: 56x56 pixels
- **Standard (Moving/Normal)**: 48x48 pixels
- **Cluster Circle**: 40x40 pixels

### Indicator Badge Dimensions
- **Diameter**: 14-16px
- **Icon Size**: 8-10px
- **Border Width**: 1.5-2px

### Motion Trail Dots
- **Dot Diameter**: 4px
- **Dot Count**: 3 (for moving state)
- **Spacing**: 6px between dots

### Selection State
- **Scale**: 1.15x normal size when selected
- **Border**: Thicker white border (3.5px vs 2.5px)

---

## Icon Library

### Main Vehicle Icons
- **Car (Front View)**: `Icons.directions_car` or custom car icon
- **Movement Symbol**: `Icons.sync` or circular rotation arrow

### Status Icons
- **Ignition Indicator**: Always `Icons.power_settings_new_rounded` (⏻) with color indicating state (Green=ON, Red=OFF, Grey=Neutral/disconnected)

---

## Zoom Level Behavior

### Zoom Levels
- **Zoom ≤ 8**: Compact markers (48x48)
- **Zoom 9-10**: Transition zone (compact unless selected)
- **Zoom ≥ 11**: Full markers (56x56)

### Selection Override
- Selected markers always use larger size (56x56)
- Selection scale applies at all zoom levels (+15%)

---

## Implementation Checklist

### State Detection Logic
```dart
// Determine marker state
final MarkerState state;
if (!online && !engineOn) {
  state = MarkerState.offlineIgnitionOff; // State 5 - Yellow/Amber
} else if (!online) {
  state = MarkerState.offline; // State 4 - Grey
} else if (moving && engineOn) {
  state = MarkerState.onlineMoving; // State 2 - Green with motion trail
} else if (engineOn) {
  state = MarkerState.onlineStopped; // State 1 - Green pin with power icon
} else {
  state = MarkerState.onlineIdleIgnitionOff; // State 3 - Green with red X
}
```

### Color Selection
```dart
Color getMarkerColor(bool online, bool moving, bool engineOn) {
  if (!online && !engineOn) return Color(0xFFFFC107); // Amber warning
  if (!online) return Color(0xFF9E9E9E); // Grey offline
  return Color(0xFFA6CD27); // Green active
}
```

### Indicator Badge
```dart
Widget buildIgnitionIndicator(bool online, bool engineOn) {
  if (!online) {
    return Badge(
      color: Colors.red,
      icon: Icons.close,
      iconColor: Colors.white,
    );
  }
  if (engineOn) {
    return Badge(
      color: Color(0xFFFF9800), // Orange for moving
      icon: Icons.power_settings_new_rounded,
      iconColor: Colors.white,
    );
  }
  return Badge(
    color: Colors.red,
    icon: Icons.close,
    iconColor: Colors.white,
  );
}
```

---

## Design Files Reference

### Source Images
1. `state-1-online-ignition-on-stopped.png` - Green pin with power indicator
2. `state-2-online-ignition-on-moving.png` - Green circle with motion dots
3. `state-3-online-ignition-off-stopped.png` - Green circle with red X
4. `state-4-offline-disconnected.png` - Grey circle with red X
5. `state-5-offline-ignition-off.png` - Amber circle with red X

---

## Accessibility Considerations

### Color Contrast
- All icons use white on colored backgrounds for maximum contrast
- Minimum contrast ratio: 4.5:1 (WCAG AA)
- Status indicators have additional border for visibility

### Size
- Minimum touch target: 48x48px (meets WCAG guidelines)
- Clear visual hierarchy through size and color

### Motion
- Motion trails provide additional movement feedback beyond color
- Static alternative: Single dot for non-moving states

---

## Future Enhancements

### Potential Additions
- [ ] Direction arrow for moving markers
- [ ] Battery level indicator
- [ ] Signal strength indicator
- [ ] Custom vehicle type icons (truck, van, motorcycle)
- [ ] Speed badge with actual km/h value
- [ ] Route preview line
- [ ] Cluster count badge styling

---

## Version History
- **v1.0** (2025-10-17): Initial design specification based on provided marker designs

---

## Notes
- All markers use Material Design 3 principles
- Animations should be subtle (< 300ms)
- Markers should maintain readability at all zoom levels
- Consider performance: Pre-render bitmap markers for clusters
- Use CustomPainter for efficient rendering
