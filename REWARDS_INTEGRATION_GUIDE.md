# Rewards Feature - Integration Guide

**Quick Start**: 5 minutes to integrate into your LENV app  
**Updated**: December 15, 2025

---

## ⚡ Step 1: Update Router (2 minutes)

Add this to your main router configuration file (typically `lib/config/router.dart` or `main.dart`):

```dart
import 'package:lenv/features/rewards/rewards_module.dart';

// In your GoRouter configuration:
GoRouter(
  routes: [
    // ... existing routes ...
    
    // Add rewards routes
    GoRoute(
      path: 'rewards',
      builder: (context, state) => const RewardsCatalogScreen(),
      routes: RewardsModule.getRoutes(),
    ),
    
    // Or if you prefer individual routes:
    ...RewardsModule.getRoutes(),
  ],
);
```

---

## ⚡ Step 2: Add Dependencies (1 minute)

Update your `pubspec.yaml`:

```yaml
dependencies:
  # Already likely installed:
  flutter_riverpod: ^2.0.0
  go_router: ^10.0.0
  cloud_firestore: ^4.0.0
  
  # Add if missing:
  freezed_annotation: ^2.0.0
  json_serializable: ^6.0.0

dev_dependencies:
  build_runner: ^2.0.0
  freezed: ^2.0.0
```

Run `flutter pub get`

---

## ⚡ Step 3: Enable Riverpod (Optional but Recommended)

Wrap your app with Riverpod:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}
```

---

## ⚡ Step 4: Add Dummy Data (2 minutes)

1. Ensure `assets/dummy_rewards.json` exists (already created)
2. Update `pubspec.yaml` assets:

```yaml
flutter:
  assets:
    - assets/dummy_rewards.json
    # ... existing assets ...
```

---

## ⚡ Step 5: Deploy Firebase Rules & Functions (Optional)

### Option A: Deploy Everything
```bash
# From project root
firebase deploy --only firestore:rules,functions:rewards
```

### Option B: Deploy Just Rules
```bash
firebase deploy --only firestore:rules
```

### Option C: Deploy Just Functions
```bash
cd functions/rewards
npm install
firebase deploy --only functions:rewards
```

---

## 🧪 Step 6: Test Integration (2 minutes)

### Test 1: Navigate to Catalog
```dart
// In any screen
context.go('/rewards/catalog');

// Or use helper
RewardsModule.navigateToCatalog(context);
```

### Test 2: Add to Menu/Drawer
```dart
ListTile(
  leading: Icon(Icons.card_giftcard),
  title: Text('Rewards'),
  onTap: () => RewardsModule.navigateToCatalog(context),
)
```

### Test 3: Verify Providers Work
```dart
// In any ConsumerWidget
@override
Widget build(BuildContext context, WidgetRef ref) {
  final catalogAsync = ref.watch(rewardsCatalogProvider);
  // Should show loading, data, or error state
}
```

---

## 📦 Integration Points

### 1. User Authentication
The system expects user ID in context. Ensure you have:
- `studentId` - Current user's student ID (if student)
- `parentId` - Current user's parent ID (if parent)
- `adminId` - Admin ID (if admin, for manual purchases)

### 2. Firestore Connection
Verify Firestore is initialized:
```dart
import 'package:firebase_core/firebase_core.dart';

// In main()
await Firebase.initializeApp();
```

### 3. Real-Time Points Display (Optional)
Add points display in app header:
```dart
// In your app header/AppBar
Consumer(
  builder: (context, ref, child) {
    final pointsAsync = ref.watch(
      studentPointsProvider(currentStudentId)
    );
    
    return pointsAsync.when(
      data: (points) => Text('${points.toInt()} pts'),
      loading: () => SizedBox(width: 50, child: Skeleton()),
      error: (e, st) => Text('--'),
    );
  },
)
```

---

## 🎨 Customization

### Change Colors
Update `rewards_module.dart` and screens:
```dart
// Primary action color
const Color(0xFFF2800D)  // Orange

// Change to your brand color:
const Color(0xFF5B21B6)  // Purple example
```

Then update all widget usages.

### Change Lock Duration
In `lib/features/rewards/utils/date_utils.dart`:
```dart
static Timestamp getLockExpirationTime() {
  return Timestamp.fromDate(
    DateTime.now().add(Duration(days: 21))  // Change 21 to your value
  );
}
```

### Disable Feature
In `rewards_module.dart`:
```dart
static bool isEnabled = false;  // Set to false to hide
```

---

## 🔐 Security Configuration

### 1. Update Firestore Rules
Make sure these are deployed:
```bash
firebase deploy --only firestore:rules
```

### 2. Set User Roles
The system expects custom claims in Firebase Auth:
```javascript
// Firebase console → User management
{
  "role": "student",  // or "parent" or "admin"
  "studentId": "student-001",
  "parentId": "parent-001"  // if parent
}
```

### 3. Update Environment Variables
Create `.env` or update Firebase config:
```
FEATURE_REWARDS=true
REWARDS_AFFILIATE_TAG=lenv-21
POINTS_PER_RUPEE=0.8
```

---

## 🚨 Troubleshooting

### Issue: "Products not loading"
**Solution**: 
- Check if Firestore is connected
- Verify `dummy_rewards.json` is in assets
- Check browser console for Firebase errors

### Issue: "Cannot create request"
**Solution**:
- Verify studentId is set correctly
- Check Firestore security rules are deployed
- Ensure student has sufficient points

### Issue: "Providers not updating"
**Solution**:
- Wrap app with `ProviderScope`
- Verify Firestore listeners are active
- Check console for Riverpod errors

### Issue: "Cloud Functions not triggering"
**Solution**:
- Verify functions are deployed: `firebase functions:list`
- Check function logs: `firebase functions:log`
- Ensure Firestore rules allow function access

---

## 📱 Add to Navigation Menu

### Example: Bottom Navigation
```dart
BottomNavigationBar(
  items: [
    BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
    BottomNavigationBarItem(icon: Icon(Icons.card_giftcard), label: 'Rewards'),
    BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
  ],
  onTap: (index) {
    if (index == 1) {
      RewardsModule.navigateToCatalog(context);
    }
  },
)
```

### Example: Drawer
```dart
Drawer(
  child: ListView(
    children: [
      DrawerHeader(child: Text('Menu')),
      ListTile(
        leading: Icon(Icons.card_giftcard),
        title: Text('Rewards'),
        onTap: () {
          Navigator.pop(context);
          RewardsModule.navigateToCatalog(context);
        },
      ),
    ],
  ),
)
```

---

## 📊 Monitoring

### Firebase Console
1. Go to `console.firebase.google.com`
2. Select your project
3. Navigate to **Firestore** → Collections:
   - `rewards_catalog` - Product count
   - `reward_requests` - Request volume
   - `notifications` - Notification queue
   - `audit_logs` - Change history

### Cloud Functions
1. Go to **Cloud Functions** in Firebase Console
2. Check logs for any errors
3. Monitor execution time

### Analytics (if enabled)
1. Go to **Analytics** dashboard
2. Filter by `rewards` screen
3. Track user engagement

---

## ✅ Pre-Launch Checklist

- [ ] Router configuration updated
- [ ] Dependencies installed (`flutter pub get`)
- [ ] ProviderScope added to app
- [ ] Firestore initialized
- [ ] Firebase rules deployed
- [ ] Cloud functions deployed
- [ ] Dummy data loaded
- [ ] Test navigation to catalog
- [ ] Test product request flow
- [ ] Test parent approval flow
- [ ] Verify real-time updates
- [ ] Check Firebase logs for errors
- [ ] Test on physical device
- [ ] Test with real Firestore data
- [ ] Add to navigation menu
- [ ] Update app version number
- [ ] Create release notes

---

## 📞 Quick Help

### Navigate Programmatically
```dart
// Go to catalog
context.go('/rewards/catalog');

// Go to product detail
context.go('/rewards/product/product-001', extra: productModel);

// Go to student requests
context.go('/rewards/requests/student/student-001');

// Go to parent dashboard  
context.go('/rewards/requests/parent/parent-001');
```

### Access Providers in Widget
```dart
Consumer(
  builder: (context, ref, child) {
    final catalog = ref.watch(rewardsCatalogProvider);
    final points = ref.watch(studentPointsProvider('student-001'));
    return YourWidget();
  },
)
```

### Trigger Actions
```dart
// Create request
ref.read(createRequestProvider.notifier).createRequest(
  studentId: 'student-001',
  productId: 'product-001',
  price: 15000,
  pointsRequired: 1200,
);

// Update status
ref.read(updateRequestStatusProvider.notifier).updateStatus(
  requestId: 'request-001',
  newStatus: RewardRequestStatus.approvedPurchaseInProgress,
);
```

---

## 🎓 Architecture Overview

```
User Interface (5 Screens)
    ↓
Riverpod Providers (11 Providers)
    ↓
Repository Layer (RewardsRepository)
    ↓
Firestore (Real-time Listeners)
    ↓
Cloud Functions (Backend Logic)
    ↓
Firestore Rules (Security)
```

**Data Flow**: UI → Providers → Repository → Firestore → Cloud Functions → Audit Logs

---

## 🚀 Production Deployment

### Step 1: Update Version
```yaml
# pubspec.yaml
version: 1.0.0+1  # Increment as needed
```

### Step 2: Build Release
```bash
# Android
flutter build appbundle --release

# iOS
flutter build ios --release

# Web
flutter build web --release
```

### Step 3: Deploy Firebase
```bash
firebase deploy --only firestore:rules,functions:rewards
```

### Step 4: Monitor
- Check Firebase logs
- Monitor Cloud Function errors
- Track user engagement
- Review Firestore quota usage

---

## 📚 Documentation Files

**In your project**:
- `lib/features/rewards/README.md` - Complete implementation guide (910 lines)
- `REWARDS_IMPLEMENTATION_COMPLETE.md` - Project overview
- `REWARDS_FILE_MANIFEST.md` - File listing with descriptions

**In Firebase Console**:
- Cloud Functions logs
- Firestore audit logs
- Analytics events

---

## ✨ You're All Set!

The Rewards feature is fully integrated and ready to use. Start by:

1. Running the app: `flutter run`
2. Navigating to `/rewards/catalog`
3. Creating a test request
4. Testing parent approval flow
5. Monitoring Firebase logs

For issues, refer to the README.md in the rewards module or check the troubleshooting section above.

**Happy rewarding! 🎉**
