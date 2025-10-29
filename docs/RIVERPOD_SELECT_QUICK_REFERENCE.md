# Riverpod `.select()` Quick Reference - Code Templates

> **Quick copy-paste templates for form optimization with Riverpod**

---

## 📋 Template 1: State Model

```dart
// lib/features/my_feature/models/my_form_state.dart

import 'package:flutter/foundation.dart';

@immutable
class MyFormState {
  final String email;
  final String password;
  final bool isLoading;
  final String? errorMessage;
  
  const MyFormState({
    this.email = '',
    this.password = '',
    this.isLoading = false,
    this.errorMessage,
  });
  
  MyFormState copyWith({
    String? email,
    String? password,
    bool? isLoading,
    String? errorMessage,
  }) {
    return MyFormState(
      email: email ?? this.email,
      password: password ?? this.password,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MyFormState &&
          email == other.email &&
          password == other.password &&
          isLoading == other.isLoading &&
          errorMessage == other.errorMessage;
  
  @override
  int get hashCode => Object.hash(email, password, isLoading, errorMessage);
}
```

---

## 📋 Template 2: StateNotifier

```dart
// lib/features/my_feature/providers/my_form_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/my_feature/models/my_form_state.dart';

class MyFormNotifier extends StateNotifier<MyFormState> {
  MyFormNotifier() : super(const MyFormState());
  
  void setEmail(String email) {
    state = state.copyWith(email: email);
  }
  
  void setPassword(String password) {
    state = state.copyWith(password: password);
  }
  
  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }
  
  void setError(String? error) {
    state = state.copyWith(errorMessage: error, isLoading: false);
  }
  
  void reset() {
    state = const MyFormState();
  }
}

final myFormProvider = StateNotifierProvider.autoDispose<
    MyFormNotifier,
    MyFormState
>((ref) => MyFormNotifier());
```

---

## 📋 Template 3: Text Field with .select()

```dart
// lib/features/my_feature/widgets/email_field.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/my_feature/providers/my_form_provider.dart';

class EmailField extends ConsumerWidget {
  const EmailField({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ ONLY rebuilds when email changes
    final email = ref.watch(
      myFormProvider.select((state) => state.email),
    );
    
    return TextFormField(
      initialValue: email,
      decoration: const InputDecoration(
        labelText: 'Email',
        prefixIcon: Icon(Icons.email_outlined),
      ),
      keyboardType: TextInputType.emailAddress,
      onChanged: (value) {
        ref.read(myFormProvider.notifier).setEmail(value);
      },
      validator: (value) {
        if (value == null || value.isEmpty) return 'Email is required';
        if (!value.contains('@')) return 'Invalid email';
        return null;
      },
    );
  }
}
```

---

## 📋 Template 4: Password Field with Toggle

```dart
// lib/features/my_feature/widgets/password_field.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/my_feature/providers/my_form_provider.dart';

// Add to state model:
// final bool obscurePassword;

// Add to notifier:
// void togglePasswordVisibility() {
//   state = state.copyWith(obscurePassword: !state.obscurePassword);
// }

class PasswordField extends ConsumerWidget {
  const PasswordField({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ Watches TWO specific fields
    final password = ref.watch(
      myFormProvider.select((state) => state.password),
    );
    
    final obscurePassword = ref.watch(
      myFormProvider.select((state) => state.obscurePassword),
    );
    
    return TextFormField(
      initialValue: password,
      obscureText: obscurePassword,
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          onPressed: () {
            ref.read(myFormProvider.notifier).togglePasswordVisibility();
          },
        ),
      ),
      onChanged: (value) {
        ref.read(myFormProvider.notifier).setPassword(value);
      },
      validator: (value) {
        if (value == null || value.isEmpty) return 'Password is required';
        if (value.length < 6) return 'Min 6 characters';
        return null;
      },
    );
  }
}
```

---

## 📋 Template 5: Submit Button with Loading

```dart
// lib/features/my_feature/widgets/submit_button.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/my_feature/providers/my_form_provider.dart';

class SubmitButton extends ConsumerWidget {
  const SubmitButton({
    required this.onPressed,
    required this.label,
    super.key,
  });
  
  final VoidCallback onPressed;
  final String label;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ ONLY rebuilds when loading state changes
    final isLoading = ref.watch(
      myFormProvider.select((state) => state.isLoading),
    );
    
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}
```

---

## 📋 Template 6: Error Message Banner

```dart
// lib/features/my_feature/widgets/error_banner.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/my_feature/providers/my_form_provider.dart';

class ErrorBanner extends ConsumerWidget {
  const ErrorBanner({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ ONLY rebuilds when error message changes
    final errorMessage = ref.watch(
      myFormProvider.select((state) => state.errorMessage),
    );
    
    if (errorMessage == null || errorMessage.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## 📋 Template 7: Checkbox with .select()

```dart
// lib/features/my_feature/widgets/remember_me_checkbox.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/my_feature/providers/my_form_provider.dart';

// Add to state model:
// final bool rememberMe;

// Add to notifier:
// void setRememberMe(bool value) {
//   state = state.copyWith(rememberMe: value);
// }

class RememberMeCheckbox extends ConsumerWidget {
  const RememberMeCheckbox({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ ONLY rebuilds when checkbox state changes
    final rememberMe = ref.watch(
      myFormProvider.select((state) => state.rememberMe),
    );
    
    return CheckboxListTile(
      title: const Text('Remember me'),
      value: rememberMe,
      onChanged: (value) {
        if (value != null) {
          ref.read(myFormProvider.notifier).setRememberMe(value);
        }
      },
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
```

---

## 📋 Template 8: Slider with .select()

```dart
// lib/features/my_feature/widgets/radius_slider.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/my_feature/providers/my_form_provider.dart';

// Add to state model:
// final double radius;

// Add to notifier:
// void setRadius(double value) {
//   state = state.copyWith(radius: value);
// }

class RadiusSlider extends ConsumerWidget {
  const RadiusSlider({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ ONLY rebuilds when radius changes
    final radius = ref.watch(
      myFormProvider.select((state) => state.radius),
    );
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Radius'),
            Text(
              '${radius.toStringAsFixed(0)} m',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: radius,
          min: 50,
          max: 5000,
          divisions: 99,
          label: '${radius.toStringAsFixed(0)} m',
          onChanged: (value) {
            ref.read(myFormProvider.notifier).setRadius(value);
          },
        ),
      ],
    );
  }
}
```

---

## 📋 Template 9: Dropdown with .select()

```dart
// lib/features/my_feature/widgets/priority_dropdown.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/my_feature/providers/my_form_provider.dart';

// Add to state model:
// final String priority;

// Add to notifier:
// void setPriority(String value) {
//   state = state.copyWith(priority: value);
// }

class PriorityDropdown extends ConsumerWidget {
  const PriorityDropdown({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ ONLY rebuilds when priority changes
    final priority = ref.watch(
      myFormProvider.select((state) => state.priority),
    );
    
    return DropdownButtonFormField<String>(
      value: priority,
      decoration: const InputDecoration(
        labelText: 'Priority',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'low', child: Text('Low')),
        DropdownMenuItem(value: 'normal', child: Text('Normal')),
        DropdownMenuItem(value: 'high', child: Text('High')),
        DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
      ],
      onChanged: (value) {
        if (value != null) {
          ref.read(myFormProvider.notifier).setPriority(value);
        }
      },
    );
  }
}
```

---

## 📋 Template 10: Switch/Toggle with .select()

```dart
// lib/features/my_feature/widgets/notification_toggle.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/my_feature/providers/my_form_provider.dart';

// Add to state model:
// final bool notificationsEnabled;

// Add to notifier:
// void setNotifications(bool value) {
//   state = state.copyWith(notificationsEnabled: value);
// }

class NotificationToggle extends ConsumerWidget {
  const NotificationToggle({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ ONLY rebuilds when toggle state changes
    final notificationsEnabled = ref.watch(
      myFormProvider.select((state) => state.notificationsEnabled),
    );
    
    return SwitchListTile(
      title: const Text('Enable Notifications'),
      subtitle: const Text('Receive alerts for important events'),
      secondary: const Icon(Icons.notifications_outlined),
      value: notificationsEnabled,
      onChanged: (value) {
        ref.read(myFormProvider.notifier).setNotifications(value);
      },
    );
  }
}
```

---

## 📋 Template 11: Complete Form Page Assembly

```dart
// lib/features/my_feature/presentation/my_form_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/my_feature/widgets/email_field.dart';
import 'package:my_app_gps/features/my_feature/widgets/password_field.dart';
import 'package:my_app_gps/features/my_feature/widgets/submit_button.dart';
import 'package:my_app_gps/features/my_feature/widgets/error_banner.dart';
import 'package:my_app_gps/features/my_feature/providers/my_form_provider.dart';

class MyFormPage extends ConsumerStatefulWidget {
  const MyFormPage({super.key});
  
  @override
  ConsumerState<MyFormPage> createState() => _MyFormPageState();
}

class _MyFormPageState extends ConsumerState<MyFormPage> {
  final _formKey = GlobalKey<FormState>();
  
  @override
  void dispose() {
    // Reset form state when leaving page
    ref.read(myFormProvider.notifier).reset();
    super.dispose();
  }
  
  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    
    final formState = ref.read(myFormProvider);
    final notifier = ref.read(myFormProvider.notifier);
    
    try {
      notifier.setLoading(true);
      
      // Your submission logic here
      await Future.delayed(const Duration(seconds: 2)); // Simulated API call
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Success!')),
        );
      }
    } catch (e) {
      notifier.setError('Submission failed: ${e.toString()}');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Form')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Error banner (isolated rebuilds)
                const ErrorBanner(),
                
                // Email field (isolated rebuilds)
                const EmailField(),
                const SizedBox(height: 16),
                
                // Password field (isolated rebuilds)
                const PasswordField(),
                const SizedBox(height: 24),
                
                // Add more fields as needed...
                
                // Submit button (isolated rebuilds)
                SubmitButton(
                  label: 'Submit',
                  onPressed: _handleSubmit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

---

## 🎯 Quick Patterns

### Pattern: Watch Multiple Fields in One Widget

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  // Watch multiple specific fields
  final field1 = ref.watch(myFormProvider.select((s) => s.field1));
  final field2 = ref.watch(myFormProvider.select((s) => s.field2));
  final field3 = ref.watch(myFormProvider.select((s) => s.field3));
  
  // Widget rebuilds only when ANY of these 3 fields change
  return Column(
    children: [
      Text(field1),
      Text(field2),
      Text(field3),
    ],
  );
}
```

### Pattern: Derived/Computed State

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  // Watch computed state
  final isValid = ref.watch(
    myFormProvider.select((state) {
      return state.email.isNotEmpty &&
             state.password.length >= 6 &&
             !state.isLoading;
    }),
  );
  
  return ElevatedButton(
    onPressed: isValid ? _submit : null,
    child: Text('Submit'),
  );
}
```

### Pattern: Conditional Widget Rendering

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final showAdvanced = ref.watch(
    myFormProvider.select((s) => s.showAdvancedOptions),
  );
  
  if (!showAdvanced) return const SizedBox.shrink();
  
  return Column(
    children: [
      // Advanced options...
    ],
  );
}
```

---

## 🚦 Usage Decision Tree

```
Do you have a form field?
│
├─ YES → Is it a text input?
│   │
│   ├─ YES → Use TextEditingController
│   │         (No provider needed unless shared state)
│   │
│   └─ NO → Is it a single boolean/selection?
│       │
│       ├─ YES → Use ConsumerWidget with .select()
│       │         for that specific field
│       │
│       └─ NO → Multiple related fields?
│                Use multiple .select() calls
│
└─ NO → Is it a submit button?
         Use .select() to watch isLoading only
```

---

## ✅ Checklist Before Migration

- [ ] Identify form with heavy setState() usage
- [ ] Create state model with all form fields
- [ ] Implement StateNotifier with granular setters
- [ ] Extract each form field as ConsumerWidget
- [ ] Add `.select()` for specific fields only
- [ ] Test that rebuilds are isolated
- [ ] Verify performance improvement in DevTools

---

## 🔗 Copy These Imports

```dart
// Always needed
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Your state model
import 'package:my_app_gps/features/my_feature/models/my_form_state.dart';

// Your provider
import 'package:my_app_gps/features/my_feature/providers/my_form_provider.dart';
```

---

**Status**: ✅ Ready to copy-paste and customize!
