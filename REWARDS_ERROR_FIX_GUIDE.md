# Rewards Feature Error Resolution Summary

## Status
✅ **Dependencies Added**: flutter_riverpod ^2.6.1, go_router ^14.6.2  
✅ **Core Files Fixed**: rewards_providers.dart, rewards_module.dart, product_card.dart, modals.dart, points_badge.dart  
⚠️  **Remaining**: 51 errors in 6 screen/widget files (all property name mismatches)

## Remaining Fixes Needed

All errors are simple property name replacements. Use Find & Replace (Ctrl+H) in VS Code:

### 1. Global Replacements (All Files)
| Find | Replace | Files |
|------|---------|-------|
| `request.id` | `request.requestId` | parent_dashboard, student_requests, request_detail screens |
| `product.id` | `product.productId` | rewards_catalog screen |
| `price.amount` | `price.estimatedPrice` | product_detail, rewards_catalog screens |
| `request.auditEntries` | `request.audit` | request_detail, request_card |
| `request.timesData` | `request.timestamps` | request_detail, request_card |
| `pointsData.pointsRequired` | `pointsData.required` | request_detail, request_card |
| `pointsData.lockedPoints` | `pointsData.locked` | request_detail screen |
| `pointsData.deductedPoints` | `pointsData.deducted` | request_detail screen |

### 2. File-Specific Fixes

#### **product_detail_screen.dart** (Lines 40-48)
```dart
// CURRENT (BROKEN):
final affiliateUrl = AffiliateService.buildUrl(
  source: product.source,
  identifier: product.asin ?? product.productId,
);

// FIX TO:
final affiliateUrl = AffiliateService.buildUrl(
  product.source,
  product.asin ?? product.productId,
);
```

#### **request_detail_screen.dart** (Add import at top)
```dart
import '../../utils/date_utils.dart' as reward_date_utils;
```

Then replace function calls:
- `getRemainingDays(...)` → `reward_date_utils.DateUtils.getRemainingDays(...)`
- `formatDate(...)` → `reward_date_utils.DateUtils.formatDate(...)`
- `formatDateTime(...)` → `reward_date_utils.DateUtils.formatDateTime(...)`

#### **request_detail_screen.dart** (Line 544)
```dart
// CURRENT:
pointsToRelease: request.pointsData.required,  // int

// FIX TO:
pointsToRelease: request.pointsData.required.toDouble(),
```

#### **request_detail_screen.dart** (Lines 64-65)
```dart
// CURRENT:
await repository.updateRequestStatus(
  request.id,

// FIX TO:
await repository.updateRequestStatus(
  request.requestId,
  newStatus,
  userId: 'current_user_id',  // Get from auth
```

#### **request_card.dart** (Add import at top)
```dart
import '../../utils/date_utils.dart' as reward_date_utils;
```

Then:
- `getRemainingDays(...)` → `reward_date_utils.DateUtils.getRemainingDays(...)`

#### **product_detail_screen.dart** (Lines 106, 114, 132)
```dart
// Line 106:
'\u20b9${product.price.amount}'  →  '\u20b9${product.price.estimatedPrice}'

// Line 114 (null-safe):
if (product.rating > 0)  →  if (product.rating != null && product.rating! > 0)

// Line 132 (null-safe):
'${product.rating.toStringAsFixed(1)}'  →  '${product.rating!.toStringAsFixed(1)}'
```

#### **product_card.dart** (Line 81 - already fixed but verify)
```dart
'${product.rating.toStringAsFixed(1)}'  →  '${product.rating!.toStringAsFixed(1)}'
```

#### **parent_dashboard_screen.dart** (Lines 159, 164)
```dart
'/rewards/request/${request.id}'  →  '/rewards/request/${request.requestId}'
```

#### **student_requests_screen.dart** (Lines 144, 216)
```dart
'/rewards/request/${request.id}'  →  '/rewards/request/${request.requestId}'
```

#### **rewards_catalog_screen.dart** (Lines 138-143, 155)
```dart
// Lines 138-143:
a.price.amount  →  a.price.estimatedPrice
b.price.amount  →  b.price.estimatedPrice

// Line 143 (null-safe rating):
b.rating.compareTo(a.rating ?? 0)  →  (b.rating ?? 0).compareTo(a.rating ?? 0)

// Line 155:
product.id  →  product.productId
```

## Quick Fix Script

Run this PowerShell script in `d:\new_reward\lib\features\rewards\`:

```powershell
# Fix request.id → request.requestId
Get-ChildItem -Recurse -Filter "*.dart" | ForEach-Object {
    (Get-Content $_.FullName) -replace 'request\.id([^\w])', 'request.requestId$1' | Set-Content $_.FullName
}

# Fix product.id → product.productId
Get-ChildItem -Recurse -Filter "*.dart" | ForEach-Object {
    (Get-Content $_.FullName) -replace 'product\.id([^\w])', 'product.productId$1' | Set-Content $_.FullName
}

# Fix price.amount → price.estimatedPrice
Get-ChildItem -Recurse -Filter "*.dart" | ForEach-Object {
    (Get-Content $_.FullName) -replace 'price\.amount', 'price.estimatedPrice' | Set-Content $_.FullName
}

# Fix request.auditEntries → request.audit
Get-ChildItem -Recurse -Filter "*.dart" | ForEach-Object {
    (Get-Content $_.FullName) -replace 'request\.auditEntries', 'request.audit' | Set-Content $_.FullName
}

# Fix request.timesData → request.timestamps
Get-ChildItem -Recurse -Filter "*.dart" | ForEach-Object {
    (Get-Content $_.FullName) -replace 'request\.timesData', 'request.timestamps' | Set-Content $_.FullName
}

# Fix pointsData.pointsRequired → pointsData.required
Get-ChildItem -Recurse -Filter "*.dart" | ForEach-Object {
    (Get-Content $_.FullName) -replace 'pointsData\.pointsRequired', 'pointsData.required' | Set-Content $_.FullName
}

# Fix pointsData.lockedPoints → pointsData.locked
Get-ChildItem -Recurse -Filter "*.dart" | ForEach-Object {
    (Get-Content $_.FullName) -replace 'pointsData\.lockedPoints', 'pointsData.locked' | Set-Content $_.FullName
}

# Fix pointsData.deductedPoints → pointsData.deducted
Get-ChildItem -Recurse -Filter "*.dart" | ForEach-Object {
    (Get-Content $_.FullName) -replace 'pointsData\.deductedPoints', 'pointsData.deducted' | Set-Content $_.FullName
}

Write-Host "✅ Automated replacements complete. Run 'flutter analyze lib/features/rewards/' to verify."
```

## After Fixes
1. Run: `flutter analyze lib/features/rewards/`
2. Run: `dart fix --apply lib/features/rewards/`
3. Verify: Should show 0 errors
4. Test: `flutter run`

## Model Property Reference (Correct Names)
```dart
ProductModel:
  ✅ product.productId (NOT product.id)
  ✅ product.price.estimatedPrice (NOT price.amount)
  ✅ product.rating (nullable double?)
  
RewardRequestModel:
  ✅ request.requestId (NOT request.id)
  ✅ request.audit (NOT request.auditEntries)
  ✅ request.timestamps (NOT request.timesData)
  
PointsData:
  ✅ pointsData.required (NOT pointsRequired)
  ✅ pointsData.locked (NOT lockedPoints)
  ✅ pointsData.deducted (NOT deductedPoints)
```

## Next Steps
1. Copy-paste the PowerShell script above into a terminal in the rewards folder
2. Manually fix the 3-4 complex cases (AffiliateService call, DateUtils imports, type conversions)
3. Run `flutter analyze` and `dart fix --apply`
4. Proceed to integration (follow REWARDS_INTEGRATION_GUIDE.md)
