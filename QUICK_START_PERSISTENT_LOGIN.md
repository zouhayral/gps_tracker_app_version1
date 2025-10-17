# Quick Implementation Guide - Persistent Login

## How to Use

### For Users

1. **First Login**:
   - Open the app
   - Enter your email/username and password
   - Tap "Login"
   - App navigates to map page

2. **Subsequent Opens**:
   - Open the app
   - **Automatic login happens!** 🎉
   - Map page appears instantly
   - No need to enter credentials again

3. **Logout**:
   - Tap Settings (bottom navigation)
   - Tap "Logout" button
   - Login page appears
   - Next app open will require manual login

4. **Switching Accounts**:
   - Logout from current account
   - Enter new account credentials
   - Login with new account
   - New account's devices appear
   - Auto-login enabled for new account

### For Developers

#### Testing Auto-Login

**Test 1: Enable Auto-Login**
```bash
# Run the app
flutter run

# Login with valid credentials
# Observe: You're logged in and see the map

# Hot restart the app (simulates app reopen)
# Press 'R' in terminal

# Observe: Auto-login happens, map appears immediately
```

**Test 2: Logout Clears Auto-Login**
```bash
# While logged in, navigate to Settings
# Tap "Logout"
# Observe: Login page appears

# Hot restart the app
# Observe: Login page appears (no auto-login)
```

**Test 3: Wrong Server Credentials**
```bash
# Login and enable auto-login
# Change password on Traccar server
# Hot restart the app
# Observe: Error message "Session expired. Please login again."
```

#### Debugging

**Check Stored Credentials** (for debugging only):
```dart
// Add to auth_notifier.dart for debugging
Future<void> debugCheckStoredCredentials() async {
  final email = await _secure.read(key: _storedEmailKey);
  final hasPassword = await _secure.read(key: _storedPasswordKey) != null;
  debugPrint('Stored email: $email');
  debugPrint('Has password: $hasPassword');
}
```

**Monitor Auth State Changes**:
```dart
// In your app, add a listener
ref.listen(authNotifierProvider, (previous, next) {
  debugPrint('Auth state changed: ${next.runtimeType}');
});
```

**View Auto-Login Flow**:
- Check logs for:
  - `[Auth] Attempting auto-login...` (not implemented, but would be useful)
  - Login success/failure messages
  - State transitions

#### Implementation Details

**Files Modified**:
- `lib/features/auth/controller/auth_notifier.dart` (main changes)

**Key Methods**:
1. `_bootstrap()` - Auto-login on app startup
2. `login()` - Save credentials on successful login
3. `logout()` - Clear credentials on logout
4. `_clearStoredCredentials()` - Helper to clear secure storage

**Storage Keys**:
```dart
'stored_email'     → User's email (encrypted in FlutterSecureStorage)
'stored_password'  → User's password (encrypted in FlutterSecureStorage)
'last_email'       → Last login email (in SharedPreferences for UI)
```

**Security Notes**:
- Credentials stored using OS-level secure storage
- iOS: Keychain (protected by biometrics if enabled)
- Android: EncryptedSharedPreferences (Android Keystore)
- Web: Secure browser storage
- Credentials never logged or printed
- All caches cleared on logout

## Troubleshooting

### Issue: Auto-login not working
**Symptoms**: Login page shown every time

**Possible Causes**:
1. Credentials not stored (login failed previously)
2. Server session expired
3. Network connectivity issues

**Solution**:
- Login manually once
- Check network connection
- Verify server is accessible

### Issue: Wrong user data shown
**Symptoms**: Old user's devices visible after logout

**Possible Causes**:
- Caches not cleared properly
- Multiple devices using same credentials

**Solution**:
- Clear app data (Settings → Apps → GPS Tracker → Clear Data)
- Reinstall app
- Verify logout clears caches (check code)

### Issue: "Session expired" on every app open
**Symptoms**: Auto-login fails repeatedly

**Possible Causes**:
- Server credentials changed
- Server session invalidated
- Network issues during auto-login

**Solution**:
- Login manually with current password
- New credentials will be stored
- Auto-login will work with new credentials

## Configuration

### Disable Auto-Login (Optional)

If you want to disable auto-login for security reasons:

```dart
// In auth_notifier.dart, modify _bootstrap():
Future<void> _bootstrap() async {
  final prefs = await SharedPreferences.getInstance();
  final lastEmail = prefs.getString(_lastEmailKey);
  
  // Comment out auto-login logic
  // Just show login page
  state = AuthInitial(lastEmail: lastEmail);
  
  // Original auto-login code commented out below
  // ...
}
```

### Change Auto-Login Behavior

**Make auto-login optional with checkbox**:
```dart
// Add a checkbox on login page
final shouldRemember = useState(true);

// In login method:
if (shouldRemember.value) {
  await _secure.write(key: _storedEmailKey, value: email);
  await _secure.write(key: _storedPasswordKey, value: password);
}
```

**Add biometric confirmation before auto-login**:
```dart
// Add local_auth package to pubspec.yaml
// In _bootstrap(), before auto-login:
final auth = LocalAuthentication();
final didAuthenticate = await auth.authenticate(
  localizedReason: 'Authenticate to access your account',
);
if (!didAuthenticate) {
  state = AuthUnauthenticated(lastEmail: storedEmail);
  return;
}
// Proceed with auto-login
```

## Best Practices

### For Users
1. ✅ Use strong passwords
2. ✅ Enable device lock (PIN/biometric)
3. ✅ Logout on shared devices
4. ✅ Keep app updated

### For Developers
1. ✅ Never log credentials
2. ✅ Clear credentials on logout
3. ✅ Handle auto-login failures gracefully
4. ✅ Test account switching
5. ✅ Monitor error rates

## Performance

**App Startup Time**:
- Without auto-login: ~500ms (show login page)
- With auto-login: ~1.5-2s (network call + device fetch)
- **User perception**: Better (instant access vs manual login)

**Memory Usage**:
- Credentials: ~200 bytes in secure storage
- Negligible impact on app performance

**Battery Impact**:
- One additional network call on startup
- Same as manual login, no extra overhead

## Next Steps

After implementing, consider:
1. Add biometric authentication (TouchID/FaceID)
2. Implement refresh tokens (reduce credential validation)
3. Add "Remember me" checkbox (optional auto-login)
4. Monitor auto-login success rates via analytics
5. Add session duration settings

---

**Need Help?**
- Check logs for auth state transitions
- Verify network connectivity
- Test with fresh app install
- Contact support if issues persist
