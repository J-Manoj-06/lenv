# 🎨 Universal Feedback & Error Handling System

A comprehensive, role-based feedback system for Flutter applications with beautiful animations and consistent user experience.

## ✨ Features

- 🎨 **Role-based theming** - Automatic color adaptation for Student, Teacher, Parent, Institute
- 📱 **Multiple feedback types** - Snackbars, Dialogs, Banners, Loading indicators
- 🎭 **Beautiful animations** - Smooth transitions with Lottie support
- 🔄 **Network status** - Auto-detecting connection issues
- ♿ **Accessible** - High contrast, readable text
- 📦 **Reusable** - Single import, use anywhere
- 🎯 **Error-friendly** - Converts technical errors to user-friendly messages

## 🎨 Role Themes

| Role | Primary Color | Light Background | Gradient |
|------|--------------|------------------|----------|
| Student | `#F27F0D` (Orange) | `#FFF5EB` | Orange → Amber |
| Teacher | `#7E57C2` (Violet) | `#F3E5F5` | Light Purple → Deep Purple |
| Parent | `#009688` (Teal) | `#E0F2F1` | Light Teal → Teal |
| Institute | `#1976D2` (Blue) | `#E3F2FD` | Light Blue → Blue |

## 📦 Installation

### 1. Add to your project

The feedback handler is already in `lib/utils/feedback_handler.dart`

### 2. Import in your screens

```dart
import '../utils/feedback_handler.dart';
```

### 3. Add Lottie animations (Optional but recommended)

Create `assets/animations/` folder and add:
- `success.json` - Success checkmark animation
- `error.json` - Error cross animation
- `warning.json` - Warning animation
- `network.json` - Network/WiFi animation

Update `pubspec.yaml`:
```yaml
flutter:
  assets:
    - assets/animations/
```

If animations are not found, the system will fallback to Material icons.

## 📚 API Reference

### Snackbars (Bottom notifications)

#### Success Snackbar
```dart
showSuccessSnackbar(
  context,
  'Test submitted successfully!',
  role: 'student',
  duration: Duration(seconds: 3),
);
```

#### Error Snackbar
```dart
showErrorSnackbar(
  context,
  'Failed to load data.',
  role: 'teacher',
);
```

#### Warning Snackbar
```dart
showWarningSnackbar(
  context,
  'Please fill all required fields.',
  role: 'parent',
);
```

#### Info Snackbar
```dart
showInfoSnackbar(
  context,
  'New feature available!',
  role: 'institute',
);
```

### Dialogs (Modal popups)

#### Success Dialog (with Lottie)
```dart
await showSuccessDialog(
  context,
  'Your reward has been redeemed!',
  role: 'student',
  title: 'Success!',
  onDismiss: () {
    // Navigate or refresh
  },
);
```

#### Error Dialog
```dart
await showErrorDialog(
  context,
  'Invalid credentials. Please try again.',
  role: 'teacher',
  title: 'Login Failed',
  showRetry: true,
  onRetry: () {
    // Retry login logic
  },
);
```

#### Network Dialog
```dart
await showNetworkDialog(
  context,
  role: 'student',
);
```

#### Confirmation Dialog
```dart
final confirmed = await showConfirmationDialog(
  context,
  title: 'Delete Test?',
  message: 'This action cannot be undone.',
  role: 'teacher',
  confirmText: 'Delete',
  cancelText: 'Cancel',
  isDangerous: true, // Shows red/warning style
);

if (confirmed) {
  // Perform delete
}
```

#### Loading Dialog
```dart
// Show loading
showLoadingDialog(
  context,
  message: 'Uploading file...',
  role: 'student',
);

// Perform async operation
await uploadFile();

// Close loading
Navigator.of(context).pop();
```

### Banners (Top sliding notifications)

#### Generic Top Banner
```dart
showTopBanner(
  context,
  'Settings saved successfully!',
  role: 'teacher',
  type: BannerType.success,
  duration: Duration(seconds: 3),
);
```

#### Network Status Banner
```dart
// Offline
showNetworkStatusBanner(
  context,
  isOnline: false,
  role: 'student',
);

// Online
showNetworkStatusBanner(
  context,
  isOnline: true,
  role: 'student',
);
```

## 🛠️ Helper Functions

### Convert Firebase errors to friendly messages
```dart
try {
  await firebaseAuth.signIn(...);
} catch (e) {
  final friendlyMessage = getFriendlyErrorMessage(e);
  showErrorDialog(context, friendlyMessage, role: 'student');
}
```

Handles errors like:
- `user-not-found` → "No account found with this email."
- `wrong-password` → "Incorrect password. Please try again."
- `network-error` → "Check your internet connection and try again."
- And many more...

### Get role colors programmatically
```dart
final studentColor = getRoleColor('student'); // #F27F0D
final teacherLight = getRoleLightColor('teacher'); // #F3E5F5
final parentGradient = getRoleGradient('parent'); // [#4DB6AC, #009688]
```

## 💡 Usage Examples

### Login Flow
```dart
Future<void> handleLogin() async {
  // Show loading
  showLoadingDialog(context, message: 'Signing in...', role: 'student');

  try {
    await authService.login(email, password);
    
    // Close loading
    Navigator.of(context).pop();
    
    // Show success
    showSuccessSnackbar(context, 'Welcome back!', role: 'student');
    
  } catch (e) {
    // Close loading
    Navigator.of(context).pop();
    
    // Show error with retry
    showErrorDialog(
      context,
      getFriendlyErrorMessage(e),
      role: 'student',
      title: 'Login Failed',
      showRetry: true,
      onRetry: handleLogin,
    );
  }
}
```

### Test Submission
```dart
Future<void> submitTest() async {
  // Show loading
  showLoadingDialog(context, message: 'Submitting...', role: 'student');

  try {
    await testService.submit(answers);
    Navigator.of(context).pop(); // Close loading
    
    // Success with animation
    await showSuccessDialog(
      context,
      'Test submitted successfully!',
      role: 'student',
    );
    
    // Navigate to results
    Navigator.pushReplacement(...);
    
  } catch (e) {
    Navigator.of(context).pop(); // Close loading
    showErrorSnackbar(context, getFriendlyErrorMessage(e), role: 'student');
  }
}
```

### Delete Confirmation
```dart
Future<void> handleDelete(String testId) async {
  final confirmed = await showConfirmationDialog(
    context,
    title: 'Delete Test?',
    message: 'This will permanently delete the test and all student results.',
    role: 'teacher',
    confirmText: 'Delete',
    isDangerous: true,
  );

  if (confirmed) {
    showLoadingDialog(context, message: 'Deleting...', role: 'teacher');
    
    try {
      await testService.delete(testId);
      Navigator.of(context).pop(); // Close loading
      showSuccessSnackbar(context, 'Test deleted', role: 'teacher');
    } catch (e) {
      Navigator.of(context).pop();
      showErrorDialog(context, getFriendlyErrorMessage(e), role: 'teacher');
    }
  }
}
```

### Network Monitoring
```dart
class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _monitorNetworkStatus();
  }

  void _monitorNetworkStatus() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (ConnectivityResult result) {
        final isOnline = result != ConnectivityResult.none;
        
        if (!isOnline && !_wasOffline) {
          // Just went offline
          showNetworkStatusBanner(context, isOnline: false, role: 'student');
          _wasOffline = true;
        } else if (isOnline && _wasOffline) {
          // Back online
          showNetworkStatusBanner(context, isOnline: true, role: 'student');
          _wasOffline = false;
        }
      },
    );
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }
}
```

## 🎯 Best Practices

1. **Always specify role** - Ensures consistent theming
2. **Use loading dialogs** - For async operations over 1 second
3. **Provide retry options** - For network/recoverable errors
4. **Convert technical errors** - Use `getFriendlyErrorMessage()`
5. **Confirmation for dangerous actions** - Use `isDangerous: true`
6. **Auto-dismiss success** - Snackbars for quick feedback
7. **Close loading manually** - Always pop loading dialogs in try/catch

## 🎨 Customization

### Custom Colors
If you need custom colors beyond the role themes:

```dart
// In your widget
final customColor = Color(0xFF..);

ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Custom message'),
    backgroundColor: customColor,
    // ... rest of styling
  ),
);
```

### Custom Animations
Replace default Lottie animations by updating files in `assets/animations/`:
- `success.json` - Your custom success animation
- `error.json` - Your custom error animation
- `warning.json` - Your custom warning animation
- `network.json` - Your custom network animation

## 📱 Testing

Test all feedback types:
```dart
// In your test screen
ElevatedButton(
  onPressed: () => showSuccessSnackbar(context, 'Test', role: 'student'),
  child: Text('Test Success'),
),
```

See `feedback_examples.dart` for complete test implementations.

## 🐛 Troubleshooting

**Q: Lottie animations not showing?**
A: Make sure animations are in `assets/animations/` and declared in `pubspec.yaml`. The system will fallback to Material icons if files are missing.

**Q: Colors not matching my theme?**
A: Check that you're passing the correct role string: `'student'`, `'teacher'`, `'parent'`, or `'institute'` (case-insensitive).

**Q: Dialog not closing?**
A: Always use `Navigator.of(context).pop()` after async operations when using loading dialogs.

**Q: Snackbar appearing behind keyboard?**
A: Use `SnackBarBehavior.floating` (already default in this system).

## 📄 License

Part of the New Reward application. All rights reserved.

## 👨‍💻 Maintainer

For questions or issues, contact the development team.

---

**Last Updated:** November 3, 2025
