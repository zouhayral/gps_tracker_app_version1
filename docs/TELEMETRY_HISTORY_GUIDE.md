# Telemetry History Guide

This guide explains how telemetry history is persisted and displayed for each device.

## What’s included

- ObjectBox entity `TelemetryRecord` stores per-snapshot values: deviceId, timestampMs, battery, signal, speed, engine, odometer, motion.
- DAO `TelemetryDaoBase` with an ObjectBox implementation `TelemetryDaoObjectBox`.
- `telemetryHistoryProvider` returns the last 24h of history for a device.
- `TelemetryHistoryPage` shows Battery (%) and Signal charts for the last 24 hours.
- A 30-day retention job automatically purges old records on startup.

## Using the provider

```
final history = ref.watch(telemetryHistoryProvider(deviceId));

history.when(
  data: (records) { /* render charts */ },
  loading: () => const CircularProgressIndicator(),
  error: (e, _) => Text('Error: $e'),
);
```

## Showing the page

```
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => TelemetryHistoryPage(deviceId: 123),
  ),
);
```

## Retention policy

On repository startup, a background task deletes telemetry older than 30 days:

```
await telemetryDao.deleteOlderThan(DateTime.now().toUtc().subtract(const Duration(days: 30)));
```

This is fire-and-forget and won’t block the app.

## Notes

- Ensure ObjectBox code generation has been run so `TelemetryRecord` is included in `objectbox.g.dart`.
- The provider orders records ascending by timestamp for natural charting.
- Battery/Signal values may be missing for some samples; charts skip nulls.
