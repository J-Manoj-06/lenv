# LENV Rewards System - Implementation Guide

## Overview

The LENV Rewards System enables students to request products/gift cards by redeeming accumulated points. Parents can approve, manage, and confirm delivery of items. The system uses Firebase Firestore for data, Cloudflare R2 for media, and Cloud Functions for background tasks.

## Feature Structure

```
lib/features/rewards/
├── models/                    # Data models
│   ├── product_model.dart
│   ├── reward_request_model.dart
├── services/                  # Firestore & APIs
│   ├── rewards_repository.dart
│   ├── affiliate_service.dart
├── ui/
│   ├── screens/              # Full pages
│   │   ├── rewards_catalog_screen.dart
│   │   ├── product_detail_screen.dart
│   │   ├── student_requests_screen.dart
│   │   ├── parent_dashboard_screen.dart
│   │   ├── request_detail_screen.dart
│   ├── widgets/              # Reusable components
│   │   ├── product_card.dart
│   │   ├── request_card.dart
│   │   ├── confirm_modal.dart
│   │   ├── blocking_modal.dart
│   │   ├── points_badge.dart
├── providers/                 # Riverpod state management
│   └── rewards_provider.dart
├── utils/                     # Helpers
│   ├── points_calculator.dart
│   ├── date_utils.dart
├── rewards_module.dart        # Route registration

assets/
└── dummy_rewards.json        # Offline catalog fallback (50 items)

functions/rewards/
├── index.js                  # Cloud Functions (reminders, auto-resolve)
└── package.json
```

## Quick Start

### 1. Enable the Feature

In your main app navigation/routes file, add a feature flag check:

```dart
// Check if rewards feature is enabled
const bool FEATURE_REWARDS = true;

// In your navigation/bottom tabs, conditionally add:
if (FEATURE_REWARDS) {
  // Add RewardsTab or RewardsCatalogScreen
}
```

### 2. Update pubspec.yaml

Ensure these dependencies are present:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cloud_firestore: ^4.14.0
  firebase_auth: ^4.13.0
  riverpod: ^2.4.0         # or Provider if you prefer
  flutter_riverpod: ^2.4.0
  
assets:
  - assets/dummy_rewards.json
```

### 3. Initialize Firestore in Your App

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // ... other setup
  runApp(const MyApp());
}
```

### 4. Register Routes (in main app file)

```dart
import 'lib/features/rewards/rewards_module.dart';

// Add to your route table:
final routes = {
  '/rewards/catalog': (context) => const RewardsCatalogScreen(),
  '/rewards/product/:id': (context) => const ProductDetailScreen(),
  '/rewards/my-requests': (context) => const StudentRequestsScreen(),
  '/rewards/parent-dashboard': (context) => const ParentDashboardScreen(),
  '/rewards/request/:id': (context) => const RequestDetailScreen(),
};
```

Or use the RewardsModule.registerRoutes() helper.

## Firestore Collections & Rules

### Collections Needed

1. **rewards_catalog** — Product inventory
2. **reward_requests** — Student requests (pending, approved, completed, expired)
3. **students** — Extended with available_points, locked_points, deducted_points
4. **parents** — Parent contact & profile info
5. **notifications** — (optional) Push notification queue
6. **audit_logs** — (optional) All reward actions

### Security Rules

Add to your `firestore.rules`:

```firestore
match /rewards_catalog/{prod} {
  allow read: if request.auth != null;
  allow write: if false;
}

match /reward_requests/{reqId} {
  allow create: if request.auth != null 
    && request.auth.token.role == 'student'
    && request.resource.data.student_id == request.auth.uid;
  allow update: if request.auth != null && (
    (request.auth.token.role == 'parent' 
      && resource.data.parent_id == request.auth.uid)
    || request.auth.token.role == 'admin'
  );
  allow read: if request.auth != null && (
    resource.data.student_id == request.auth.uid
    || resource.data.parent_id == request.auth.uid
    || request.auth.token.role == 'admin'
  );
}
```

## State Management (Riverpod)

### Key Providers (to be implemented)

```dart
// Catalog
final rewardsCatalogProvider = FutureProvider<List<ProductModel>>((ref) async {
  return ref.watch(rewardsRepositoryProvider).getCatalog();
});

// Search
final productsSearchProvider = FutureProvider.family<List<ProductModel>, String>((ref, query) async {
  return ref.watch(rewardsRepositoryProvider).searchProducts(query);
});

// Student Points
final studentPointsProvider = StreamProvider.family<Map<String, int>, String>((ref, studentId) {
  return ref.watch(rewardsRepositoryProvider).streamStudentPoints(studentId);
});

// Student Requests
final studentRequestsProvider = StreamProvider.family<List<RewardRequestModel>, String>((ref, studentId) {
  return ref.watch(rewardsRepositoryProvider).streamStudentRequests(studentId);
});

// Parent Requests
final parentRequestsProvider = StreamProvider.family<List<RewardRequestModel>, String>((ref, parentId) {
  return ref.watch(rewardsRepositoryProvider).streamParentRequests(parentId);
});
```

## UI Components

### ProductCard
Displays product image, title, price, points required, and "Request" button.

```dart
ProductCard(
  product: productModel,
  availablePoints: 1500,
  onRequestTap: () { /* navigate to detail or show confirm modal */ },
)
```

### RequestCard
Shows request status, product snapshot, and action buttons for parent.

```dart
RequestCard(
  request: rewardRequestModel,
  onActionTap: (action) { /* update request */ },
)
```

### ConfirmModal
Modal for confirming request lock or delivery.

```dart
showDialog(
  context: context,
  builder: (_) => ConfirmModal(
    title: 'Request Reward?',
    message: 'Lock 1200 points for this item?',
    onConfirm: () { /* create request */ },
  ),
);
```

### BlockingModal
Parent entry modal if they have pending delivery confirmations.

```dart
if (hasPendingDeliveries) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlockingModal(
      requests: pendingRequests,
      onConfirmed: (requestId) { /* mark delivered */ },
    ),
  );
}
```

## Points Logic

### Creating a Request

1. Student has available_points >= required_points
2. Transaction locks points: `available_points -= required, locked_points += required`
3. Request created with status = `pending_parent_approval`

### Parent Approves & Orders

1. Parent clicks "I placed the order"
2. Request status → `awaiting_delivery_confirmation`
3. System schedules reminders (3, 7, 14 days)

### Delivery Confirmed

1. Parent clicks "Confirm delivery"
2. Request status → `completed`
3. `locked_points -= locked_amount`
4. `deducted_points += locked_amount`
5. Points stay deducted (no refund)

### Manual Purchase (Parent enters price)

1. Parent clicks "I bought it locally" → enter actual price (e.g., ₹1200)
2. deducted = min(locked, round(price * points_per_rupee))
3. released = locked - deducted
4. Update student points accordingly

### Lock Expires (Auto-Resolve)

1. After 21 days without confirmation
2. Cloud Function runs daily check
3. If lock_expires_at < now and still pending:
   - status → `expired_or_auto_resolved`
   - `locked_points -= locked_amount`
   - `available_points += locked_amount` (refund)
   - Write audit log

## Firebase Cloud Functions

Deploy to `functions/rewards/index.js` (Node 18):

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// Trigger on request creation → schedule reminders
exports.onRequestCreated = functions.firestore
  .document('reward_requests/{requestId}')
  .onCreate(async (snap, context) => {
    // Schedule reminder pubsub for day 3, 7, 14 before lock_expires_at
  });

// Daily cron → check for expired locks
exports.checkExpiredRequests = functions.pubsub
  .schedule('every day 00:00')
  .timeZone('Asia/Kolkata')
  .onRun(async (context) => {
    // Query: status in [pending_parent_approval, approved_purchase_in_progress, awaiting_delivery_confirmation]
    //        AND lock_expires_at < now
    // Update: status = expired_or_auto_resolved, release points
  });

// Manual nudge endpoint (call from parent dashboard)
exports.sendParentReminder = functions.https.onCall(async (data, context) => {
  const { requestId, parentId } = data;
  // Send SMS or push notification
});
```

## Dummy Data

The system ships with `assets/dummy_rewards.json` containing 30 sample products:

- Earbuds, headphones (₹1500–₹15000)
- Smartwatch, cameras (₹5000–₹50000)
- Laptops, tablets, TVs (₹30000–₹120000)
- Gift cards (₹500–₹2000)

**Fallback:** If Firestore catalog is empty, the app loads dummy data locally. This enables **offline testing** and **demo mode**.

## Acceptance Tests

### Test 1: Insufficient Points
- Student with 500 points tries to request item worth 1200 points
- **Expected:** Request button disabled + tooltip shows "Need 700 more points"

### Test 2: Create Request
- Student with 2000 points requests item (1200 points)
- **Expected:**
  - reward_requests doc created
  - student.available_points = 800, locked_points = 1200
  - Request appears in parent dashboard within 5s

### Test 3: Parent Approves
- Parent opens request, clicks "I placed the order"
- **Expected:**
  - Request status → awaiting_delivery_confirmation
  - Reminder schedule created

### Test 4: Parent Confirms Delivery
- Parent clicks "Confirm delivery"
- **Expected:**
  - Request status → completed
  - student.locked_points -= 1200
  - student.deducted_points += 1200
  - Audit log written

### Test 5: Auto-Expire
- Wait 21 days (or manually trigger in test)
- **Expected:**
  - Cloud Function marks request → expired_or_auto_resolved
  - Points refunded: locked → available
  - Audit logged

### Test 6: Manual Confirm with Price
- Parent clicks "I bought it locally" → enters ₹1000
- **Expected:**
  - deducted = min(1200, round(1000 * 0.8)) = 800
  - released = 1200 - 800 = 400
  - Points updated correctly

## Environment Variables (Cloud Functions)

Create `functions/.env` or set in Firebase Console:

```bash
AFFILIATE_TAG=lenv-21
REMINDER_DAYS_THRESHOLD=3,7,14
LOCK_EXPIRY_DAYS=21
CLOUDFLARE_R2_DOMAIN=files.lenv1.tech
```

## Deployment Checklist

- [ ] Add `assets/dummy_rewards.json` to pubspec.yaml
- [ ] Deploy Firestore rules (rewards_catalog, reward_requests, students, parents)
- [ ] Deploy Cloud Functions: `firebase deploy --only functions:rewards`
- [ ] Add RewardsModule to app navigation
- [ ] Set FEATURE_REWARDS=true to enable
- [ ] Test all 6 acceptance scenarios above
- [ ] Record demo video (student request → parent approve → delivery → points deducted)
- [ ] Prepare release notes

## Troubleshooting

### Catalog not loading
- Check Firestore rules allow read from `rewards_catalog`
- Verify `assets/dummy_rewards.json` exists and is in pubspec.yaml
- Check console for JSON parse errors

### Points not updating
- Verify student doc exists in Firestore (`/students/{uid}`)
- Check transaction logs in Cloud Functions
- Ensure Firestore rules allow student updates

### Parent doesn't see requests
- Verify parent_id matches parent's UID in Firestore
- Check listener stream permissions in rules
- Ensure request doc created successfully

### Reminders not sending
- Check Cloud Functions logs in Firebase Console
- Verify FCM is configured (if using push notifications)
- Check `lock_expires_at` is set correctly

## File Checklist

- [x] `lib/features/rewards/models/product_model.dart` — Product + Price + PointsRule
- [x] `lib/features/rewards/models/reward_request_model.dart` — Request + Points + Status + Audit
- [x] `lib/features/rewards/services/rewards_repository.dart` — Firestore queries + transactions
- [x] `lib/features/rewards/services/affiliate_service.dart` — URL builders
- [x] `lib/features/rewards/utils/points_calculator.dart` — Points math
- [x] `lib/features/rewards/utils/date_utils.dart` — Lock expiry + reminders
- [x] `lib/features/rewards/ui/widgets/points_badge.dart` — Points display
- [ ] `lib/features/rewards/ui/widgets/product_card.dart` — Product display (PENDING)
- [ ] `lib/features/rewards/ui/widgets/request_card.dart` — Request display (PENDING)
- [ ] `lib/features/rewards/ui/widgets/confirm_modal.dart` — Confirmation modal (PENDING)
- [ ] `lib/features/rewards/ui/widgets/blocking_modal.dart` — Entry blocking modal (PENDING)
- [ ] `lib/features/rewards/ui/screens/rewards_catalog_screen.dart` — Main catalog (PENDING)
- [ ] `lib/features/rewards/ui/screens/product_detail_screen.dart` — Product detail (PENDING)
- [ ] `lib/features/rewards/ui/screens/student_requests_screen.dart` — Student requests (PENDING)
- [ ] `lib/features/rewards/ui/screens/parent_dashboard_screen.dart` — Parent dashboard (PENDING)
- [ ] `lib/features/rewards/ui/screens/request_detail_screen.dart` — Request detail (PENDING)
- [ ] `lib/features/rewards/providers/rewards_provider.dart` — Riverpod providers (PENDING)
- [ ] `lib/features/rewards/rewards_module.dart` — Route registration (PENDING)
- [x] `assets/dummy_rewards.json` — Dummy catalog (30 products)
- [ ] `functions/rewards/index.js` — Cloud Functions (PENDING)
- [ ] `firebase/firestore.rules` — Security rules (PENDING)

## Next Steps

1. **Implement remaining UI screens** using the provided ProductCard and RequestCard widgets
2. **Set up Riverpod providers** for catalog, requests, and student points
3. **Deploy Cloud Functions** for reminder scheduling and auto-expiry
4. **Add Firestore security rules** (see above)
5. **Test all acceptance scenarios** before enabling feature flag
6. **Enable FEATURE_REWARDS=true** in production after QA approval

---

For questions or issues, refer to the main LENV project README or contact the development team.
