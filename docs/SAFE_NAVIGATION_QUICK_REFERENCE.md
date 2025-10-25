# Safe Navigation Quick Reference

## 🚀 Quick Start

Import and use safe navigation methods to prevent crashes:

```dart
import 'package:my_app_gps/core/navigation/safe_navigation.dart';

// Then use safePop(), safeGo(), safePush() instead of regular navigation
```

---

## 📋 Method Replacements

### Pop Navigation

```dart
// ❌ OLD - Can crash at root
context.pop()
Navigator.pop(context)

// ✅ NEW - Safe, redirects to map if at root
context.safePop()
context.safePop(result)  // With result value
```

### Go Navigation

```dart
// ❌ OLD - Can crash if widget disposed
context.go('/path')

// ✅ NEW - Checks mounted state
context.safeGo('/path')
context.safeGo('/path', extra: data)
```

### Push Navigation

```dart
// ❌ OLD - Can crash if widget disposed
context.push('/path')

// ✅ NEW - Checks mounted state
final result = await context.safePush('/path')
final result = await context.safePush('/path', extra: data)
```

---

## 🎯 Common Use Cases

### 1. Button Callbacks
```dart
// Back button
TextButton(
  onPressed: () => context.safePop(),
  child: Text('Back'),
)

// Navigate button
ElevatedButton(
  onPressed: () => context.safeGo('/settings'),
  child: Text('Settings'),
)
```

### 2. Async Navigation
```dart
Future<void> _loadAndNavigate() async {
  await fetchData();
  // Widget might be disposed after async work
  context.safeGo('/results');  // Safe!
}
```

### 3. Dialog Result
```dart
Future<void> _showConfirmDialog() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Confirm?'),
      actions: [
        TextButton(
          onPressed: () => context.safePop(false),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () => context.safePop(true),
          child: Text('OK'),
        ),
      ],
    ),
  );
  
  if (confirmed == true) {
    // Do something
  }
}
```

### 4. Conditional Pop
```dart
Future<void> _handleBack() async {
  if (hasUnsavedChanges) {
    final shouldDiscard = await _showDiscardDialog();
    if (shouldDiscard) {
      context.safePop();
    }
  } else {
    context.safePop();
  }
}
```

### 5. Check Before Pop
```dart
void _handleBackButton() {
  if (context.canSafelyPop) {
    // Safe to pop
    context.safePop();
  } else {
    // At root - go to map instead
    context.safeGo('/map');
  }
}
```

---

## 🔧 Advanced Patterns

### Pop and Push
```dart
// Replace current route with new one
await context.safePopAndPush('/new-route');
await context.safePopAndPush('/new-route', extra: data);
```

### Replace Current Route
```dart
// Replace without animation
context.safeReplace('/new-route');
context.safeReplace('/new-route', extra: data);
```

### Check Mounted in Callbacks
```dart
void _setupListener() {
  someStream.listen((data) {
    // Check if widget still mounted before navigation
    if (context.mounted) {
      context.safeGo('/results');
    }
  });
}
```

---

## 🎨 Migration Examples

### Example 1: Simple Back Button
```dart
// Before
AppBar(
  leading: IconButton(
    icon: Icon(Icons.arrow_back),
    onPressed: () => context.pop(),
  ),
)

// After
AppBar(
  leading: IconButton(
    icon: Icon(Icons.arrow_back),
    onPressed: () => context.safePop(),
  ),
)
```

### Example 2: Form Submission
```dart
// Before
Future<void> _submitForm() async {
  await saveData();
  context.go('/success');
}

// After
Future<void> _submitForm() async {
  await saveData();
  context.safeGo('/success');
}
```

### Example 3: Dialog Actions
```dart
// Before
AlertDialog(
  actions: [
    TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text('Cancel'),
    ),
  ],
)

// After
AlertDialog(
  actions: [
    TextButton(
      onPressed: () => context.safePop(),
      child: Text('Cancel'),
    ),
  ],
)
```

---

## ⚠️ When NOT to Use

Safe navigation is NOT needed for:

1. **showDialog/showModalBottomSheet**: These return results safely
2. **Named routes within dialogs**: Dialog context handles lifecycle
3. **StaticRoutes**: These don't participate in navigation stack

---

## 🐛 Debugging

If you see these logs, safe navigation is working:

```
[SafeNav] ⚠️ Context not mounted, skipping pop
[SafeNav] ⚠️ At root, redirecting to map
[SafeNav] ✅ Popped route successfully
[SafeNav] ✅ Navigated to /settings
```

If you see router errors in logs:

```
[Router] ❌ Navigation error: ...
[Router] 🔄 Redirecting to map page
```

This means error boundary caught an issue and recovered gracefully!

---

## 📊 Benefits

- ✅ **No crashes** from popping last page
- ✅ **No crashes** from disposed widgets
- ✅ **Automatic recovery** to map page
- ✅ **Debug logging** for troubleshooting
- ✅ **Drop-in replacement** for existing methods

---

## 🎯 Recommendation

**Critical Paths (High Priority):**
- Main app back buttons
- Dialog dismiss actions
- Async navigation after data loading
- Deep link handling

**Normal Paths (Medium Priority):**
- Settings navigation
- Form submissions
- List item taps

**Low Risk Paths (Optional):**
- Navigation within stable contexts
- Routes without async work

---

## 📞 Need Help?

See `docs/CRASH_FIXES_COMPREHENSIVE.md` for full implementation details and troubleshooting.
