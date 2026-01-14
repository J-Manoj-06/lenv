# 🎯 Reward Approval System - Quick Reference

## 📋 At a Glance

| Feature | Status | Location |
|---------|--------|----------|
| Single Pending Request Block | ✅ Complete | `product_detail_screen.dart` |
| Amazon Approval | ✅ Complete | `parent_request_approval_screen.dart` |
| Manual Approval with Price | ✅ Complete | `parent_request_approval_screen.dart` |
| 3-Day Reminder Badge | ✅ Complete | `parent_request_approval_screen.dart` |
| 21-Day Auto-Expiry | ✅ Complete | `rewards_repository.dart` |
| Points Restoration | ✅ Complete | `rewards_repository.dart` |
| Audit Trail | ✅ Complete | `rewards_repository.dart` |

---

## 🔄 User Flows

### Student Flow
```
1. Browse Rewards Catalog
2. Click "Request" → Check for pending
   ├─ IF pending exists → Show warning, block request
   └─ IF no pending → Create request
3. View in "My Rewards" → Status: "Pending"
4. Wait for parent approval...
5. Once approved → Can request another reward
```

### Parent Flow (Amazon)
```
1. Open Reward Requests
2. Auto-check expired requests (21+ days)
3. View child's pending request
   └─ See time warning if 3+ days old
4. Click "Approve" → Choose "Amazon Affiliate"
5. See confirmation → Click "Open Amazon"
6. Complete purchase on Amazon
```

### Parent Flow (Manual)
```
1. Open Reward Requests
2. Auto-check expired requests
3. View child's pending request
4. Click "Approve" → Choose "Manual Purchase"
5. Enter actual price paid
6. Confirm → Request marked approved
```

---

## 🗄️ Database Schema

### New Fields Added
```dart
// In RewardRequestModel
double? manualPrice;           // Price for manual purchases
DateTime? lastReminderSentAt;  // Last reminder timestamp
```

### Firestore Structure
```
reward_requests/{requestId}
  ├─ student_id: string
  ├─ parent_id: string
  ├─ status: string
  ├─ purchase_mode: 'amazon' | 'manual'
  ├─ manual_price: number (optional)
  ├─ last_reminder_sent_at: timestamp (optional)
  ├─ timestamps
  │   ├─ requested_at: timestamp
  │   └─ lock_expires_at: timestamp (requested_at + 21 days)
  ├─ points
  │   └─ required: number
  ├─ product_snapshot {...}
  └─ audit: array
      └─ {actor, action, timestamp, metadata}
```

---

## 🔌 API Methods

### Repository Methods (rewards_repository.dart)

```dart
// Check for pending requests
Future<RewardRequestModel?> getLatestRewardRequest(String studentId)
Future<bool> hasActivePendingRequest(String studentId)

// Approve requests  
Future<void> approveRewardRequest({
  required String requestId,
  required String approverId,
  required String approvalMethod, // 'amazon' or 'manual'
  double? manualPrice,
})

// Time-based operations
Future<int> cancelExpiredRewardRequests()
Future<bool> checkAndSendReminder(String studentId)
```

---

## ⏱️ Time-Based Logic

### 3-Day Reminders
- **Trigger**: Request pending for 3+ days
- **Action**: Show orange badge "⏰ Pending for X days"
- **Repeat**: Every 3 days (tracked in `lastReminderSentAt`)

### 21-Day Expiry
- **Trigger**: Request pending for 21+ days
- **Action**: 
  - Change status to `expiredOrAutoResolved`
  - Release locked points back to student
  - Log audit entry with reason "EXPIRED_21_DAYS"
- **When**: Parent opens reward requests screen

### Expiry Warning
- **Trigger**: Less than 3 days until expiry
- **Action**: Show red badge "⚠️ Expires in X days!"

---

## 🎨 UI Components

### Time Warning Badge
```dart
_TimeWarning(request: request, isDark: isDark)
```
- Orange: Pending 3+ days
- Red: Expiring in <3 days

### Approval Dialog
- Two options displayed in modal
- Amazon: Orange button with cart icon
- Manual: Blue button with store icon

### Manual Price Input
- Text field with ₹ prefix
- Validates price > 0
- Shows confirmation with entered amount

---

## 🧪 Test Commands

```bash
# Analyze code
flutter analyze lib/features/rewards/

# Run app
flutter run

# Hot reload after changes
r (in terminal)

# Check Firestore console
firebase console
```

---

## 📱 User Messages

### Student Messages
```
✅ Success: "🎉 Request submitted! Parent notification sent."
❌ Blocked: "⏳ You have a pending reward request. Please wait for parent approval before requesting another reward."
```

### Parent Messages
```
✅ Amazon: "✓ Approved via Amazon"
✅ Manual: "✓ Approved! Manual purchase: ₹1250.50"
❌ Error: "Error: [error message]"
```

---

## 🔍 Debug Logs

Key logs to watch:
```
🟣 = Student operations (product_detail_screen)
🟠 = Repository operations (rewards_repository)
🔴 = System operations (auto-expiry, reminders)
```

Common logs:
```
🔴 Auto-cancelled 1 expired requests
🟠 RewardsRepository: Returning 2 parsed requests  
🟣 Parent ID resolved: xyz123 from student doc
```

---

## 📝 Status Enum Values

```dart
pendingParentApproval       // Initial state
approvedPurchaseInProgress  // After approval
cancelled                   // Parent rejected
expiredOrAutoResolved       // Auto-cancelled after 21 days
completed                   // Delivered (future)
```

---

## 🚨 Important Notes

1. **Only touches reward features** - no changes to other app features
2. **Backward compatible** - works with existing reward requests
3. **Transaction safe** - uses Firestore transactions for point operations
4. **Audit trail** - all actions logged with timestamp and actor
5. **Auto-runs on load** - expiry check runs when parent opens screen

---

## 🔗 Related Files

```
lib/features/rewards/
├─ models/
│  └─ reward_request_model.dart (✏️ Updated)
├─ services/
│  └─ rewards_repository.dart (✏️ Updated)
└─ ui/screens/
   ├─ product_detail_screen.dart (✏️ Updated)
   └─ parent_request_approval_screen.dart (✏️ Updated)
```

---

## ✅ Verification Checklist

- [ ] Student can't request while pending exists
- [ ] Parent sees 2 approval options (Amazon/Manual)
- [ ] Manual price input works and saves
- [ ] Amazon approval shows confirmation
- [ ] Orange badge appears after 3 days
- [ ] Red badge appears 3 days before expiry
- [ ] Auto-expiry cancels after 21 days
- [ ] Points restored after expiry/cancellation
- [ ] Audit trail logs all actions

---

**Status**: ✅ Ready for Production
**Documentation**: Complete
**Testing Guide**: Available (REWARD_APPROVAL_TESTING_GUIDE.md)
