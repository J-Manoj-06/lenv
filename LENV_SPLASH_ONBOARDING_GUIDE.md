# 🚀 Dynamic Splash Screen & Onboarding Flow Implementation Guide

## 📋 Overview

This implementation provides a complete dynamic splash screen and onboarding flow for the Lenv app with support for:
- **First-time users**: Automatic onboarding → School Selection → Dashboard
- **Returning users**: Dynamic splash with school branding → Dashboard
- **Clean Architecture**: Reusable widgets and services
- **Automatic Theme**: System light/dark mode support
- **Local Storage**: SharedPreferences for school data persistence

---

## 📁 File Structure

### New Files Created:

```
lib/
├── constants/
│   └── app_colors.dart                    # Color constants with light/dark themes
├── services/
│   └── school_storage_service.dart        # SharedPreferences for school data
└── screens/onboarding/
    ├── enhanced_splash_screen.dart        # Dynamic splash (default or custom)
    ├── onboarding_screen.dart             # Main onboarding with PageView
    ├── onboarding_page_widget.dart        # Reusable page widget
    └── school_selection_screen.dart       # School selection interface
```

### Updated Files:

```
lib/
├── main.dart                              # Added school storage initialization
├── constants/app_colors.dart              # Updated with new color constants
├── core/theme/app_theme.dart              # Already supports system theme
├── routes/app_router.dart                 # Added new routes
└── providers/theme_provider.dart          # Already supports ThemeMode.system
```

---

## 🎨 Color Scheme

### Primary Color
- **Light Orange**: `#FFA726` (main branding color)
- Used in buttons, highlights, indicators, and UI accents

### Theme Colors
- **Light Theme**: White background with light orange accent
- **Dark Theme**: Black/dark grey background with orange accent
- **Automatic**: Uses `ThemeMode.system` to respect device settings

---

## 🔄 App Flow

### First-Time User (No School Selected)
```
1. Enhanced Splash Screen (Default Lenv branding)
   ↓
2. Onboarding Screen (3 swipeable pages)
   ↓
3. School Selection Screen
   ↓
4. Role Selection Screen
   ↓
5. Dashboard (Role-based)
```

### Returning User (School Selected)
```
1. Enhanced Splash Screen (Custom school branding)
   ↓
2. Dashboard (Directly)
```

---

## 📱 Screens Breakdown

### 1. **Enhanced Splash Screen** (`enhanced_splash_screen.dart`)
- **Duration**: 2-3 seconds with fade-in animation
- **Default (No School)**:
  - Lenv logo with "Learning Ecosystem" tagline
  - Smooth gradient background
- **Custom (School Selected)**:
  - School logo
  - School name
  - "Powered by Lenv" text
- **Animation**: Fade + slide-up effect

### 2. **Onboarding Screen** (`onboarding_screen.dart`)
- **3 Swipeable Pages** using `PageView`
- **Page 1**: "One App for Your Entire School"
  - Icon: People group
  - Description: Community message
- **Page 2**: "Everything You Need, In One Place"
  - Icon: Dashboard
  - Bullet points: Assignments, Attendance, Announcements, Communication
- **Page 3**: "Secure, Reliable, and Ready"
  - Icon: Security
  - Description: Data safety message
- **Controls**:
  - Skip button (top right) → School Selection
  - Page indicators (animated dots)
  - Next/Get Started button (bottom)

### 3. **School Selection Screen** (`school_selection_screen.dart`)
- Mock list of schools with logos
- Quick selection with school card UI
- Manual entry option for unlisted schools
- Saves to `SharedPreferences`

---

## 🔐 Data Persistence

### SchoolStorageService
Manages persistent data using `SharedPreferences`:

```dart
// Store school data
await schoolStorageService.saveSchoolData(
  schoolId: 'school_001',
  schoolName: 'Central High School',
  schoolLogo: 'https://...',
  themeColor: '#FFA726',
);

// Check if school selected
if (schoolStorageService.isSchoolSelected) {
  // School exists
}

// Get stored data
String? schoolId = schoolStorageService.schoolId;
String? schoolName = schoolStorageService.schoolName;
String? schoolLogo = schoolStorageService.schoolLogo;

// Clear on logout
await schoolStorageService.clearSchoolData();
```

---

## 🛣️ New Routes

### Added Routes:

```dart
// Enhanced splash screen
'/' → EnhancedSplashScreen()

// Onboarding (3 pages)
'/onboarding' → OnboardingScreen()

// School selection
'/school-selection' → SchoolSelectionScreen()

// Existing routes remain unchanged
'/role-selection' → RoleSelectionScreen()
'/teacher-login' → TeacherLoginScreen()
// ... etc
```

---

## 🌗 Theme Implementation

### Default: System Theme
The app automatically uses the device's light/dark mode preference via `ThemeMode.system`.

### Light Theme
- Background: White (`#FFFFFF`)
- Primary: Light Orange (`#FFA726`)
- Text: Dark (`#212121`)
- Cards: Light grey (`#FAFAFA`)

### Dark Theme
- Background: Black (`#121212`)
- Primary: Light Orange (`#FFA726`)
- Text: Light (`#FFFFFF`)
- Cards: Dark grey (`#1E1E1E`)

**Theme Configuration** (`core/theme/app_theme.dart`):
```dart
MaterialApp(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: themeProvider.themeMode,  // Uses ThemeMode.system
)
```

---

## 🎯 Usage Examples

### Initialize School Storage
```dart
await schoolStorageService.initialize();
```

### Check Onboarding Status
```dart
bool hasSeenOnboarding = schoolStorageService.hasSeenOnboarding;
bool isSchoolSelected = schoolStorageService.isSchoolSelected;
```

### Save School Data
```dart
await schoolStorageService.saveSchoolData(
  schoolId: 'sch_123',
  schoolName: 'Central High',
  schoolLogo: 'https://example.com/logo.png',
);
```

### Programmatic Navigation
```dart
// Skip onboarding
Navigator.pushReplacementNamed(context, '/school-selection');

// After school selection
Navigator.pushReplacementNamed(context, '/role-selection');
```

---

## ✅ UI/UX Features

### Animations
- **Fade-in**: Logo and text fade in smoothly (1.2s)
- **Slide-up**: Content slides up with fade
- **Page indicators**: Smooth animation between dots
- **Button effects**: Ripple on press

### Responsive Design
- **Scalable fonts**: Uses `Theme.of(context).textTheme`
- **Flexible layout**: Handles various screen sizes
- **Safe areas**: Notch/status bar compatibility

### Accessibility
- **Touch targets**: 56px minimum height for buttons
- **Color contrast**: High contrast for text
- **Clear hierarchy**: Visual weight guides attention

---

## 🔧 Customization Guide

### Change Primary Color
Edit `lib/constants/app_colors.dart`:
```dart
static const Color primary = Color(0xFFFFA726);  // Change this
```

### Add More Onboarding Pages
Edit `lib/screens/onboarding/onboarding_screen.dart`:
```dart
// In PageView children
OnboardingPage(
  title: 'Page 4: Title',
  description: 'Content here...',
  icon: Icons.your_icon,
),
```

### Change Splash Duration
Edit `lib/screens/onboarding/enhanced_splash_screen.dart`:
```dart
await Future.delayed(const Duration(seconds: 3));  // Change duration
```

### Mock Different Schools
Edit `lib/screens/onboarding/school_selection_screen.dart`:
```dart
final List<Map<String, String>> mockSchools = [
  // Add more schools
];
```

---

## 🧪 Testing

### Test First-Time User Flow
```dart
// Clear all preferences
await schoolStorageService.clearSchoolData();
// Restart app
// Should show: Splash → Onboarding → School Selection
```

### Test Returning User Flow
```dart
// Set school data
await schoolStorageService.saveSchoolData(
  schoolId: 'test_school',
  schoolName: 'Test School',
  schoolLogo: 'https://...',
);
// Restart app
// Should show: Custom Splash → Dashboard
```

### Test Dark Mode
```dart
// Android: Settings > Display > Dark theme
// iOS: Settings > Display & Brightness > Dark
// App automatically adapts
```

---

## 📚 Dependencies

All required dependencies are already in `pubspec.yaml`:
- ✅ `shared_preferences: ^2.5.3` - Data persistence
- ✅ `lottie: ^3.1.2` - Animations (optional)
- ✅ `provider: ^6.1.2` - State management
- ✅ `flutter` - Core framework

---

## 🐛 Troubleshooting

### Splash screen not showing school logo
- Check school logo URL is valid
- Verify network connectivity
- Logo will fallback to icon if URL is invalid

### Onboarding not appearing first time
- Verify `schoolStorageService.initialize()` is called in `main()`
- Check `hasSeenOnboarding` flag in SharedPreferences
- Clear app data to reset

### Theme not matching system settings
- Verify `ThemeMode.system` is set in `AppTheme`
- Check device theme settings
- Restart app after changing device theme

### Routes not resolving
- Ensure new imports in `app_router.dart`
- Check route names match exactly
- Verify GoRouter/MaterialApp routing setup

---

## 📝 Next Steps

1. **Deploy**: Build APK/IPA and test on devices
2. **Customize**: Update colors, text, and assets
3. **API Integration**: Connect school selection to backend
4. **Analytics**: Track onboarding completion
5. **A/B Testing**: Test different onboarding flows

---

## 💡 Pro Tips

1. **Reusable Pages**: `OnboardingPage` widget can be used elsewhere
2. **Custom Splash**: Update school logo dynamically from API
3. **Themed Navigation**: All screens respect light/dark theme
4. **Performance**: All storage operations are async/await safe
5. **Analytics**: Add tracking to onboarding completion

---

## 📞 Support

For issues or questions:
1. Check the `troubleshooting` section above
2. Verify all imports are correct
3. Ensure SharedPreferences data is accessible
4. Check network connectivity for image loading

---

Generated: March 29, 2026
Created for: Lenv Educational App
