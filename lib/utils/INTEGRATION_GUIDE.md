# 🚀 Quick Integration Guide - Feedback System

## Step 1: Lottie Animations Setup

### Download Free Lottie Animations

Visit [LottieFiles](https://lottiefiles.com/) and download these animations:

1. **Success Animation** → Search "success checkmark" or "check circle"
   - Save as: `assets/animations/success.json`
   - Recommended: Green checkmark with circular motion

2. **Error Animation** → Search "error" or "cross mark"
   - Save as: `assets/animations/error.json`
   - Recommended: Red X or error symbol

3. **Warning Animation** → Search "warning" or "alert"
   - Save as: `assets/animations/warning.json`
   - Recommended: Yellow exclamation mark

4. **Network Animation** → Search "wifi" or "no internet"
   - Save as: `assets/animations/network.json`
   - Recommended: WiFi signal with loading animation

### Alternative: Use These Direct Links

```
Success: https://lottiefiles.com/animations/success-check-mark-animation
Error: https://lottiefiles.com/animations/error-cross-animation
Warning: https://lottiefiles.com/animations/warning-alert-animation
Network: https://lottiefiles.com/animations/no-wifi-animation
```

## Step 2: Update pubspec.yaml

Ensure these dependencies exist:
```yaml
dependencies:
  flutter:
    sdk: flutter
  lottie: ^3.0.0  # Already in your project

flutter:
  assets:
    - assets/animations/  # Add this line
```

## Step 3: Create Directory Structure

Run in terminal:
```bash
mkdir -p assets/animations
```

Or manually create:
```
new_reward/
├── assets/
│   ├── animations/
│   │   ├── success.json
│   │   ├── error.json
│   │   ├── warning.json
│   │   └── network.json
```

## Step 4: Quick Test

Add to any screen:
```dart
import '../utils/feedback_handler.dart';

// In your widget
ElevatedButton(
  onPressed: () {
    showSuccessSnackbar(context, 'Test successful!', role: 'student');
  },
  child: Text('Test Feedback'),
),
```

## Step 5: Integration Examples

### Replace existing error handling:

**BEFORE:**
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('Error occurred')),
);
```

**AFTER:**
```dart
showErrorSnackbar(context, 'Error occurred', role: 'student');
```

### Replace existing loading:

**BEFORE:**
```dart
showDialog(
  context: context,
  builder: (_) => Center(child: CircularProgressIndicator()),
);
```

**AFTER:**
```dart
showLoadingDialog(context, message: 'Loading...', role: 'student');
```

### Replace AlertDialog:

**BEFORE:**
```dart
showDialog(
  context: context,
  builder: (_) => AlertDialog(
    title: Text('Error'),
    content: Text('Something went wrong'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text('OK')),
    ],
  ),
);
```

**AFTER:**
```dart
showErrorDialog(
  context,
  'Something went wrong',
  role: 'student',
  title: 'Error',
);
```

## Step 6: Implement Role Detection

Add to your auth provider or main app:

```dart
class AuthProvider extends ChangeNotifier {
  String _userRole = 'student'; // student, teacher, parent, institute

  String get userRole => _userRole;

  void setUserRole(String role) {
    _userRole = role;
    notifyListeners();
  }
}
```

Use in screens:
```dart
final authProvider = Provider.of<AuthProvider>(context);
showSuccessSnackbar(context, 'Success!', role: authProvider.userRole);
```

## Step 7: Network Monitoring (Optional)

Add to your main app:
```dart
dependencies:
  connectivity_plus: ^5.0.0
```

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkMonitor {
  static void initialize(BuildContext context, String role) {
    bool wasOffline = false;
    
    Connectivity().onConnectivityChanged.listen((result) {
      final isOnline = result != ConnectivityResult.none;
      
      if (!isOnline && !wasOffline) {
        showNetworkStatusBanner(context, isOnline: false, role: role);
        wasOffline = true;
      } else if (isOnline && wasOffline) {
        showNetworkStatusBanner(context, isOnline: true, role: role);
        wasOffline = false;
      }
    });
  }
}
```

## Step 8: Test All Roles

Create a test screen:
```dart
import '../utils/feedback_examples.dart';

// Navigate to test screen
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => CompleteLoginFlowExample(role: 'student'),
  ),
);
```

## Common Integration Points

### Login Screen
```dart
try {
  showLoadingDialog(context, message: 'Signing in...', role: 'student');
  await authService.login(email, password);
  Navigator.pop(context); // Close loading
  showSuccessSnackbar(context, 'Welcome back!', role: 'student');
} catch (e) {
  Navigator.pop(context);
  showErrorDialog(
    context,
    getFriendlyErrorMessage(e),
    role: 'student',
    showRetry: true,
    onRetry: () => handleLogin(),
  );
}
```

### Test Submission
```dart
showLoadingDialog(context, message: 'Submitting test...', role: 'student');
try {
  await submitTest();
  Navigator.pop(context);
  await showSuccessDialog(
    context,
    'Test submitted successfully!',
    role: 'student',
  );
} catch (e) {
  Navigator.pop(context);
  showErrorSnackbar(context, getFriendlyErrorMessage(e), role: 'student');
}
```

### Delete Actions
```dart
final confirmed = await showConfirmationDialog(
  context,
  title: 'Delete Item?',
  message: 'This cannot be undone.',
  role: 'teacher',
  isDangerous: true,
);

if (confirmed) {
  // Proceed with deletion
}
```

### Form Validation
```dart
if (emailController.text.isEmpty) {
  showWarningSnackbar(
    context,
    'Please enter your email.',
    role: 'student',
  );
  return;
}
```

## Troubleshooting Checklist

- [ ] Lottie package in pubspec.yaml
- [ ] Assets folder declared in pubspec.yaml
- [ ] Animation JSON files in assets/animations/
- [ ] Run `flutter pub get`
- [ ] Correct role string passed ('student', 'teacher', 'parent', 'institute')
- [ ] Context is valid (not after Navigator.pop)
- [ ] Loading dialogs are closed with Navigator.pop()

## Performance Tips

1. **Don't create dialogs in build method** - Use callbacks
2. **Close loading before showing result** - Always pop loading first
3. **Reuse role value** - Store in provider instead of passing repeatedly
4. **Lazy load Lottie** - Animations load on-demand (built-in)

## Next Steps

1. ✅ Setup animations
2. ✅ Test with all roles
3. ✅ Replace existing feedback in app
4. ✅ Add network monitoring
5. ✅ Test on physical device
6. ✅ Update error handling globally

---

**Ready to use!** Import and start showing beautiful, role-themed feedback! 🎉
