# Reward System - Quick Start Testing Guide

## 🎬 Getting Started

### Prerequisites
- App is running: `flutter run`
- Student is logged in
- Parent is logged in (separate device/window)

---

## ⚡ Quick Test Flows

### Flow 1: Student Requests a Reward (5 minutes)

**Steps**:

1. **Open Rewards Tab**
   - Student: Tap "Rewards" in bottom nav
   - See: Rewards Catalog with list of products
   - Verify: "Your Points: XXX" shows at top

2. **Search/Browse Products**
   - Tap search icon or scroll
   - Try: Search "gaming" or sort by price
   - See: Products filtered/sorted correctly

3. **View Product Detail**
   - Tap any product card
   - See: Premium detail screen with:
     - Product image placeholder
     - Title and price
     - **Eligibility Card** showing:
       - "Points Needed: X points"
       - "Your Points: Y points" (in green if eligible)
       - "✓ You can request this reward" (if eligible)

4. **Request the Reward**
   - Tap "Request Reward" button
   - Dialog appears: "Request [Product] for X points?"
   - Tap "Request"
   - See: Success snackbar "✓ Request submitted!"
   - Verify: Auto-navigates back

5. **View "My Rewards"**
   - See: RewardsTopSwitcher at top
   - Tap: "My Rewards" button
   - See: Your request appears in list
   - Status: Shows "Pending Approval" badge (orange)

---

### Flow 2: Parent Approves Request (5 minutes)

**Prerequisites**: Student completed Flow 1

**Steps**:

1. **Parent Opens Request Approval Screen**
   - Parent: Navigate to Rewards section
   - Route: `/rewards/parent-approvals/{parentId}`
   - See: List of pending requests from children

2. **View Request Details**
   - See: Product name, points required, request date
   - See: Status badge "Pending" (orange)
   - See: Two action buttons: "Reject" | "Approve"

3. **Approve Request**
   - Tap: "Approve" button
   - Dialog: "Approve [Product] for X points?"
   - Tap: "Approve"
   - See: Success snackbar "✓ Request approved!"
   - Notice: Status badge changes to "Approved" (green)

4. **Student Checks Update**
   - Student: Go to "My Rewards" tab
   - Refresh screen
   - See: Request status now shows "Order in Progress"

---

### Flow 3: Insufficient Points Handling (3 minutes)

**Steps**:

1. **Find Expensive Product**
   - Browse catalog
   - Find product with points > your current balance
   - Example: If you have 200 points, find 1000+ point product

2. **Try to Request**
   - Tap product
   - See: Eligibility card shows:
     - "Need 800 more points" (orange warning)
     - Your points in orange/red color
   - Request button: **DISABLED**
   - Button label: "Need 800 Points"

3. **Verify Button Disabled**
   - Try tapping request button
   - Nothing happens (disabled state)

---

### Flow 4: "My Rewards" Tab Navigation (2 minutes)

**Steps**:

1. **From Catalog**
   - On RewardsCatalogScreen
   - See: RewardsTopSwitcher at top
   - "Catalog" button highlighted (orange)
   - "My Rewards" button not highlighted

2. **Switch to My Rewards**
   - Tap "My Rewards" button
   - Navigate to StudentRequestsScreen
   - "My Rewards" button now highlighted

3. **Filter by Status**
   - Tap status filter chips
   - "All" | "Pending" | "In Progress" | "Delivery" | "Completed"
   - Each shows relevant requests

4. **Back to Catalog**
   - Tap "Catalog" button
   - Return to RewardsCatalogScreen
   - Catalog button highlighted again

---

## 🔍 What to Verify

### Student Side ✅
- [ ] Catalog loads products from Firestore or dummy JSON
- [ ] Search filters by title/description
- [ ] Sort by price works (low→high, high→low)
- [ ] Points display is live (from student_rewards)
- [ ] Product detail shows correct price + required points
- [ ] Eligibility card color-codes correctly (green eligible, orange insufficient)
- [ ] Request button disabled when insufficient points
- [ ] Request submission creates Firestore document
- [ ] My Rewards tab shows all requests
- [ ] Request status matches Firestore data
- [ ] Top switcher navigation works (Catalog ↔ My Rewards)
- [ ] Empty states display nicely (no data errors)

### Parent Side ✅
- [ ] Parent approval screen loads requests from Firestore
- [ ] Requests show correct product, points, date
- [ ] Status badges render correctly (Pending orange, Approved green, etc.)
- [ ] Approve button works (status updates in Firestore)
- [ ] Reject button works (marks request as cancelled)
- [ ] Success/error messages display
- [ ] Real-time updates via stream (no manual refresh needed)

### Error Handling ✅
- [ ] Empty request list shows empty state (not error)
- [ ] Network errors show gracefully
- [ ] Missing points data defaults to 0
- [ ] Malformed Firestore docs don't crash app
- [ ] Dialog dismisses correctly

---

## 🐛 Debugging Tips

### Check Points Display
Open DevTools Console and search for:
```
studentPointsProvider watching -> {studentId}
```

Should see loading → data with a number.

### Check Request Creation
When submitting request, look for:
```
✓ Creating reward request for student={id}, parent={id}
```

Check Firestore `reward_requests` collection after request:
```
{
  request_id: "auto-generated",
  student_id: "{studentId}",
  parent_id: "{parentId}",
  product_snapshot: {...},
  points: { required: 100, locked: 100, deducted: 0 },
  status: "pendingParentApproval",
  timestamps: { requestedAt: ..., lockExpiresAt: ... },
  audit: [{ actor, action, timestamp }]
}
```

### Check Approval
After parent approves, status should change to:
```
status: "approvedPurchaseInProgress"
audit: [
  { actor: "studentId", action: "requested", ... },
  { actor: "parentId", action: "approvedPurchaseInProgress", ... }
]
```

---

## 🎯 Success Criteria

**System is working correctly when**:

1. ✅ Student can browse 5+ products
2. ✅ Student can request a reward
3. ✅ Request appears in "My Rewards" immediately
4. ✅ Parent can see student's request
5. ✅ Parent can approve/reject request
6. ✅ Student sees status update in real-time
7. ✅ Points show correctly (not 0)
8. ✅ Disabled state works for insufficient points
9. ✅ Empty states show instead of errors
10. ✅ Navigation between tabs is smooth

---

## 📊 Test Data Setup

### Sample Products (Firestore)
```json
rewards_catalog/{productId}:
{
  "productId": "gaming-headset-001",
  "title": "Gaming Headset Pro",
  "description": "Premium wireless gaming headset",
  "price": {
    "estimatedPrice": 250,
    "currency": "INR"
  },
  "pointsRule": {
    "pointsPerRupee": 2,
    "maxPoints": 1000
  },
  "rating": 4.5,
  "status": "available",
  "source": "amazon",
  "asin": "B08EXAMPLE"
}
```

### Sample Student Data
```json
students/{studentId}:
{
  "available_points": 500,
  "locked_points": 0,
  "deducted_points": 0
}

student_rewards/{studentId}-2024:
{
  "studentId": "{studentId}",
  "pointsEarned": 500,
  "month": "December",
  "year": 2024
}
```

---

## ⏱️ Expected Performance

| Action | Time |
|--------|------|
| Load catalog | < 1s |
| Search products | < 500ms |
| Open product detail | < 500ms |
| Submit request | < 2s |
| Reload My Rewards | < 1s |
| Parent sees new request | < 2s (stream delay) |
| Approve request | < 2s |

---

## 🆘 If Something Breaks

### "Error loading requests" on My Rewards

**Check**:
1. Is `reward_requests` collection empty?
   - That's OK! Empty state should show.
2. Did request submission fail?
   - Check Firestore > `reward_requests` collection
   - Should have at least 1 document
3. Is the query failing?
   - Check browser console for red errors
   - Look for "Error streaming student requests"

**Fix**:
- Create a test request manually in Firestore
- Verify document has `student_id` and `timestamps.requested_at`
- Hard refresh page (Ctrl+R)

### Request button doesn't work

**Check**:
1. Are points sufficient?
   - Button should be disabled if not enough points
2. Is `studentId` null?
   - Check RewardsScreenWrapper receives userId
3. Did dialog dismiss without action?
   - Try tapping button again

**Fix**:
- Verify `RewardsScreenWrapper` called with `userId: user.uid`
- Check console for "Error submitting request: ..."
- Try requesting a cheaper product first

### Parent can't see requests

**Check**:
1. Is `parentId` correct?
   - Should match student's parent_id in documents
2. Are requests in Firestore?
   - Check `reward_requests` collection exists
   - Verify documents have `parent_id` field
3. Is parent logged in with right ID?
   - Check auth user UID matches document `parent_id`

**Fix**:
- Manually set `parent_id` in request document
- Verify parent user ID in Firestore users collection
- Check security rules allow read access

---

## 📈 Monitoring

To track system health:

1. **Firestore Usage**: Monitor reads/writes
   - Each request creation: 1-2 writes
   - Each stream subscription: 1 read per doc change
   - Each approval: 1-2 writes

2. **Real-time Lag**: Check stream updates
   - Should be < 2 seconds from action to UI update
   - Verify `snapshots()` subscription working

3. **Error Rate**: Monitor console errors
   - Should have 0 unhandled exceptions
   - All errors should print with ❌ prefix

---

**Happy Testing! 🚀**

For detailed implementation docs, see: `REWARD_SYSTEM_COMPLETE.md`
