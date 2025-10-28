# Analytics Date Filter Fix

## Problem Description

The Reports & Statistics page was showing incorrect data compared to the Trips page when filtering by the same date and device.

### Example Issue:
- **Trips Page**: Shows 6 trips for device "fmb920" on Oct 27, 2025 ✅
- **Reports Page**: Shows 82 trips for the same device on "Today" ❌

### Root Cause:

The analytics system had a hardcoded limitation where:
1. The "Day" filter was **always** using `DateTime.now()` (today's date)
2. There was no way to select a **specific date** from the calendar
3. The UI showed "Today" but was actually loading data from the current timestamp, not the selected date
4. Weekly and Monthly periods were also hardcoded to end "today"

This meant that even if you wanted to view analytics for a specific past date, the system would always fetch data for the current day.

## Solution Implemented

### 1. Added `selectedDateProvider` to Analytics Providers

**File**: `lib/features/analytics/controller/analytics_providers.dart`

```dart
/// Provider for the selected date when using 'daily' period.
///
/// This allows the calendar picker to control which specific day's
/// data is displayed. When null, defaults to today.
final selectedDateProvider = StateProvider<DateTime?>((ref) => null);
```

This provider stores the date selected by the user from the calendar picker.

### 2. Updated `effectiveDateRangeProvider` Logic

**Before**:
```dart
final now = DateTime.now(); // Always today!

switch (period) {
  case 'daily':
    final startOfDay = DateTime(now.year, now.month, now.day);
    // ...
}
```

**After**:
```dart
final selectedDate = ref.watch(selectedDateProvider);
final referenceDate = selectedDate ?? DateTime.now(); // Use selected date if available

switch (period) {
  case 'daily':
    final startOfDay = DateTime(referenceDate.year, referenceDate.month, referenceDate.day);
    final endOfDay = DateTime(referenceDate.year, referenceDate.month, referenceDate.day, 23, 59, 59);
    return DateTimeRange(start: startOfDay, end: endOfDay);
  
  case 'weekly':
    // 7 days ending on referenceDate (not always today!)
    final startOfWeek = referenceDate.subtract(const Duration(days: 7));
    // ...
  
  case 'monthly':
    // 30 days ending on referenceDate (not always today!)
    final startOfMonth = referenceDate.subtract(const Duration(days: 30));
    // ...
}
```

### 3. Updated Analytics Notifier Methods

**File**: `lib/features/analytics/controller/analytics_notifier.dart`

Added optional `date` / `endDate` parameters:

```dart
Future<void> loadDaily(int deviceId, {DateTime? date}) async {
  final targetDate = date ?? DateTime.now();
  // ...
  final report = await _repository.fetchDailyReport(targetDate, deviceId);
}

Future<void> loadWeekly(int deviceId, {DateTime? endDate}) async {
  final targetDate = endDate ?? DateTime.now();
  final startDate = targetDate.subtract(const Duration(days: 7));
  // ...
}

Future<void> loadMonthly(int deviceId, {DateTime? endDate}) async {
  final targetDate = endDate ?? DateTime.now();
  final startDate = targetDate.subtract(const Duration(days: 30));
  // ...
}
```

### 4. Added Date Picker UI

**File**: `lib/features/analytics/view/analytics_page.dart`

Added a calendar button next to the period label:

```dart
IconButton(
  icon: const Icon(Icons.edit_calendar, size: 16),
  onPressed: period == 'custom' 
    ? _selectCustomDateRange 
    : _selectSingleDate,
  tooltip: period == 'custom' ? t.editPeriod : 'Select date',
)
```

Added date picker method:

```dart
Future<void> _selectSingleDate() async {
  final currentDate = ref.read(selectedDateProvider) ?? DateTime.now();

  final picked = await showDatePicker(
    context: context,
    initialDate: currentDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now(),
  );

  if (picked != null) {
    ref.read(selectedDateProvider.notifier).state = picked;
    // Listener will automatically trigger _loadReport()
  }
}
```

### 5. Added Listener for Date Changes

```dart
// Listen to selected date changes and reload
ref.listen<DateTime?>(selectedDateProvider, (previous, next) {
  if (previous != next) {
    _loadReport();
  }
});
```

### 6. Updated `_loadReport()` to Pass Selected Date

```dart
void _loadReport() {
  // ...
  final selectedDate = ref.read(selectedDateProvider);
  
  switch (period) {
    case 'daily':
      notifier.loadDaily(deviceId, date: selectedDate);
    case 'weekly':
      notifier.loadWeekly(deviceId, endDate: selectedDate);
    case 'monthly':
      notifier.loadMonthly(deviceId, endDate: selectedDate);
  }
}
```

## How to Use the Fixed Feature

### For Daily Reports:

1. Open **Reports & Statistics** page
2. Select **"Day"** period
3. Select your device from the dropdown
4. Click the **📅 calendar button** next to the date
5. Pick any date (e.g., Oct 27, 2025)
6. The report now shows data for **that specific date** (not today!)

### For Weekly Reports:

1. Select **"Week"** period
2. Click the calendar button
3. Pick an **end date** for the week
4. The report shows data for the **7 days ending on that date**

### For Monthly Reports:

1. Select **"Month"** period
2. Click the calendar button
3. Pick an **end date** for the month
4. The report shows data for the **30 days ending on that date**

### For Custom Range:

1. Select **"Custom"** period
2. Click the calendar button
3. Pick a **date range** with start and end dates
4. The report shows data for that exact range

## Before vs After

### Before Fix:

| Period | What Displayed | Can Change Date? |
|--------|----------------|------------------|
| Day    | Always TODAY   | ❌ No           |
| Week   | Last 7 days from TODAY | ❌ No |
| Month  | Last 30 days from TODAY | ❌ No |
| Custom | Selected range | ✅ Yes |

### After Fix:

| Period | What Displayed | Can Change Date? |
|--------|----------------|------------------|
| Day    | Selected date OR today | ✅ Yes |
| Week   | 7 days ending on selected date | ✅ Yes |
| Month  | 30 days ending on selected date | ✅ Yes |
| Custom | Selected range | ✅ Yes |

## Technical Details

### Data Flow:

```
User clicks calendar button
       ↓
showDatePicker() opens
       ↓
User selects Oct 27, 2025
       ↓
selectedDateProvider updated
       ↓
Listener triggers _loadReport()
       ↓
effectiveDateRangeProvider recalculates
       ↓
Analytics Notifier calls API with correct date
       ↓
Traccar API: /reports/trips?deviceId=X&from=2025-10-27T00:00:00&to=2025-10-27T23:59:59
       ↓
Correct data displayed!
```

### API Calls Comparison:

**Before** (always used current date):
```
GET /api/reports/trips?deviceId=123&from=2025-10-28T00:00:00&to=2025-10-28T23:59:59
```

**After** (uses selected date):
```
GET /api/reports/trips?deviceId=123&from=2025-10-27T00:00:00&to=2025-10-27T23:59:59
```

## Testing Checklist

- [x] Can select past dates using calendar picker
- [x] Daily report shows correct data for selected date
- [x] Weekly report shows correct data ending on selected date
- [x] Monthly report shows correct data ending on selected date
- [x] Date label updates to show selected date
- [x] Changing device reloads data for selected date
- [x] Changing period maintains selected date
- [x] Calendar button works for all periods
- [x] Data matches what Trips page shows for same filter

## Files Modified

1. `lib/features/analytics/controller/analytics_providers.dart`
   - Added `selectedDateProvider`
   - Updated `effectiveDateRangeProvider` to use selected date
   - Updated `periodLabelProvider` to display selected date

2. `lib/features/analytics/controller/analytics_notifier.dart`
   - Added optional `date` parameter to `loadDaily()`
   - Added optional `endDate` parameter to `loadWeekly()`
   - Added optional `endDate` parameter to `loadMonthly()`
   - Added `_formatDate()` helper for logging

3. `lib/features/analytics/view/analytics_page.dart`
   - Added `_selectSingleDate()` method
   - Updated `_loadReport()` to pass selected date
   - Added listener for `selectedDateProvider`
   - Updated period label UI to show calendar button for all periods
   - Calendar button shows for daily/weekly/monthly (not just custom)

## Benefits

✅ **Accurate Data**: Reports now show correct data for the selected date/period
✅ **Historical Analysis**: Users can view analytics for any past date
✅ **Consistency**: Reports page now matches Trips page data
✅ **Better UX**: Clear visual indication of selected date
✅ **Flexible**: Works with all period types (daily/weekly/monthly/custom)

## Migration Notes

No migration needed. Existing code will work with default behavior (showing today's data when no date is selected).

The fix is **backward compatible**:
- If `selectedDateProvider` is `null` → uses `DateTime.now()` (current behavior)
- If `selectedDateProvider` has a value → uses that date (new behavior)

## Future Enhancements

Potential improvements:
1. Add "quick select" buttons (Yesterday, Last Week, Last Month)
2. Add date range presets in a dropdown
3. Save last selected date in preferences
4. Add "Compare" mode to compare two date ranges
5. Add date validation to prevent future dates
