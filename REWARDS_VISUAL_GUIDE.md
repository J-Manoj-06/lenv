# 🗺️ LENV REWARDS SYSTEM - VISUAL ARCHITECTURE & FLOW GUIDE

**Visual Reference for System Architecture, Data Flow, and Integration Points**

---

## 📊 System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     LENV REWARDS SYSTEM                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │           PRESENTATION LAYER (UI)                        │   │
│  │                                                            │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │   │
│  │  │   Catalog    │  │  Product     │  │   Student    │   │   │
│  │  │   Screen     │  │   Detail     │  │   Requests   │   │   │
│  │  │              │  │   Screen     │  │   Screen     │   │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │   │
│  │                                                            │   │
│  │  ┌──────────────┐  ┌──────────────┐                      │   │
│  │  │   Parent     │  │   Request    │                      │   │
│  │  │   Dashboard  │  │   Detail     │                      │   │
│  │  │   Screen     │  │   Screen     │                      │   │
│  │  └──────────────┘  └──────────────┘                      │   │
│  │                                                            │   │
│  │  Widgets: ProductCard, RequestCard, PointsBadge, Modals │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ↓                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │         STATE MANAGEMENT (Riverpod)                      │   │
│  │                                                            │   │
│  │  • rewardsCatalogProvider         (FutureProvider)      │   │
│  │  • productsSearchProvider         (FutureProvider.fam)  │   │
│  │  • studentPointsProvider          (StreamProvider.fam)  │   │
│  │  • studentRequestsProvider        (StreamProvider.fam)  │   │
│  │  • parentRequestsProvider         (StreamProvider.fam)  │   │
│  │  • createRequestProvider          (StateNotifier)       │   │
│  │  • updateRequestStatusProvider    (StateNotifier)       │   │
│  │  • filterProvider                 (StateNotifier)       │   │
│  │                                                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ↓                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │        DATA ACCESS LAYER (Repository)                    │   │
│  │                                                            │   │
│  │  RewardsRepository:                                      │   │
│  │  • getCatalog()          → Firestore + JSON fallback    │   │
│  │  • searchProducts()      → Firestore query              │   │
│  │  • createRequest()       → Transaction (atomic)         │   │
│  │  • updateRequestStatus() → Transaction validation       │   │
│  │  • streamStudentPoints() → Real-time listener           │   │
│  │  • streamRequests()      → Real-time updates            │   │
│  │                                                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ↓                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │        CLOUD DATA LAYER (Firestore)                      │   │
│  │                                                            │   │
│  │  Collections:                                            │   │
│  │  ├── rewards_catalog/        (Products)                │   │
│  │  ├── reward_requests/        (Requests)                │   │
│  │  ├── students/               (Points)                  │   │
│  │  ├── notifications/          (Events)                  │   │
│  │  └── audit_logs/             (History)                 │   │
│  │                                                            │   │
│  │  Security: Role-based rules (student/parent/admin)     │   │
│  │                                                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ↓                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │      SERVERLESS BACKEND (Cloud Functions)               │   │
│  │                                                            │   │
│  │  1. onRewardRequestCreated()                            │   │
│  │     → Create notification + audit log                  │   │
│  │                                                            │   │
│  │  2. checkExpiredRequests()                              │   │
│  │     → Daily cron (00:00 IST), release points           │   │
│  │                                                            │   │
│  │  3. onRewardRequestUpdated()                            │   │
│  │     → Log audit + send notifications                   │   │
│  │                                                            │   │
│  │  4. confirmDelivery() [HTTPS Callable]                  │   │
│  │     → Transaction: release points, update status       │   │
│  │                                                            │   │
│  │  5. sendParentReminder() [HTTPS Callable]               │   │
│  │     → Create manual reminder notification              │   │
│  │                                                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Request State Machine

```
                    ┌─────────────────────────────────┐
                    │  pendingParentApproval          │
                    │  (Parent must review/approve)   │
                    └────┬────────────────────┬────────┘
                         │                    │
                    [APPROVE]            [CANCEL]
                         │                    │
                         ↓                    ↓
              ┌─────────────────────┐    ┌────────────┐
              │ approvedPurchase    │    │ cancelled  │
              │ InProgress          │    │ (endpoint) │
              │ (item being bought) │    └────────────┘
              └────┬────────────────┘
                   │
              [PURCHASE]
                   │
                   ↓
        ┌──────────────────────────┐
        │ awaitingDelivery         │
        │ Confirmation             │
        │ (awaiting delivery proof)│
        └────┬────────────────────┬┘
             │                    │
        [CONFIRM]            [CANCEL]
             │                    │
             ↓                    ↓
        ┌────────────┐        ┌───────────┐
        │ completed  │        │ cancelled │
        │(endpoint)  │        │(endpoint) │
        └────────────┘        └───────────┘

ANY STATE ──[AUTO-EXPIRY]──→ expiredOrAutoResolved (endpoint)
            (21-day lock)
```

---

## 💰 Points Flow Diagram

```
STUDENT ACTIVITY
        ↓
   Earn Points (app integration - not in this module)
        ↓
   ┌─────────────────────────────┐
   │ available_points increase   │
   │ Example: +100 points        │
   └─────────────────────────────┘
        ↓
   REQUEST CREATION
   ┌──────────────────────────────────────┐
   │ Student creates reward request       │
   │ Product price: ₹15,000               │
   │ Points per rupee: 0.8                │
   │ Max points: 1,500                    │
   │ Formula: min(1500, round(15000×0.8)) │
   │ = min(1500, 12000) = 1,500 pts       │
   └────┬─────────────────────────────────┘
        │
        ↓ [TRANSACTION]
   ┌───────────────────────────────────────┐
   │ ATOMIC UPDATE:                        │
   │ • Check available_points >= 1500      │
   │ • Deduct 1500 from available          │
   │ • Add 1500 to locked_points           │
   │ • Create request document             │
   │ • Lock timer starts (21 days)         │
   └────┬────────────────────────────────┬─┘
        │                                │
        ↓                        [EXPIRY - 21 days]
   PARENT APPROVAL                        │
        │                                │
   ┌────┴─────────────────────┐          │
   │ Parent approves request  │          ↓
   │ (no immediate change)    │      ┌────────────────────┐
   └────┬─────────────────────┘      │ AUTO-EXPIRY CRON   │
        │                            │ (Daily 00:00 IST)  │
        ↓                            │                    │
   ┌─────────────────────────┐       │ Release locked     │
   │ Item purchased by store │       │ points back to     │
   │ (status: in progress)   │       │ available_points   │
   └────┬────────────────────┘       └────┬───────────────┘
        │                                 │
        ↓                                 ↓
   ┌──────────────────────────┐   ┌───────────────────┐
   │ DELIVERY CONFIRMATION    │   │ STATE: expired    │
   │                          │   │ (points: +1500)   │
   │ Checklist:               │   └───────────────────┘
   │ ☑ Item delivered         │
   │ ☑ Receipt verified       │
   │ ☑ Confirm button         │
   └────┬─────────────────────┘
        │
        ↓ [CLOUD FUNCTION TRANSACTION]
   ┌────────────────────────────────┐
   │ DEDUCTION (if manual item):    │
   │ • Locked: 1500                 │
   │ • Deduction fee: 5-20% (50pts) │
   │ • Released: 1450 points        │
   │                                │
   │ FINAL UPDATE:                  │
   │ • Remove 1500 from locked      │
   │ • Add 1450 to available        │
   │ • Update status: completed     │
   │ • Create audit log             │
   └────┬───────────────────────────┘
        │
        ↓
   ┌──────────────────────────┐
   │ STATE: completed         │
   │ ✓ Points: +1450 bonus    │
   │ ✓ Student happy! 🎉      │
   └──────────────────────────┘
```

---

## 🗄️ Firestore Collections Schema

```
Firestore Database
│
├── rewards_catalog/
│   └── {docId}
│       ├── id: "product-001"
│       ├── title: "AirPods Pro"
│       ├── asin: "B0B4QKV2N1"
│       ├── affiliateUrl: "https://amazon.in/..."
│       ├── price: { amount: 15000, currency: "INR" }
│       ├── pointsRule: { pointsPerRupee: 0.8, maxPoints: 1500 }
│       ├── rating: 4.5
│       ├── status: "available"
│       └── createdAt: timestamp
│
├── reward_requests/
│   └── {requestId}
│       ├── studentId: "student-001"
│       ├── status: "pending_parent_approval"
│       ├── pointsData: {
│       │   pointsRequired: 1500,
│       │   lockedPoints: 1500,
│       │   deductedPoints: 0
│       │ }
│       ├── timesData: {
│       │   createdAt: timestamp,
│       │   lockExpiresAt: timestamp (now + 21 days),
│       │   completedAt: null
│       │ }
│       ├── confirmationData: null,
│       ├── auditEntries: [
│       │   { changeType: "created", timestamp, changedBy, details },
│       │   { changeType: "status_changed", ... }
│       │ ]
│       └── metadata: { ... }
│
├── students/
│   └── {studentId}
│       ├── available_points: 500
│       ├── locked_points: 1500
│       ├── total_points_earned: 2000
│       └── metadata: { ... }
│
├── notifications/
│   └── {notificationId}
│       ├── recipientId: "parent-001"
│       ├── type: "reward_request_created"
│       ├── title: "Reward Request Pending"
│       ├── body: "Your child requested AirPods Pro"
│       ├── read: false
│       └── createdAt: timestamp
│
└── audit_logs/
    └── {logId}
        ├── changeType: "status_changed"
        ├── entityType: "reward_request"
        ├── entityId: "request-001"
        ├── oldValue: "pending_parent_approval"
        ├── newValue: "approved_purchase_in_progress"
        ├── changedBy: "parent-001"
        ├── reason: "Parent approved"
        ├── timestamp: timestamp
        └── metadata: { ... }
```

---

## 🔄 Data Flow: Request Creation

```
UI Layer (StudentScreen)
  │
  └─→ [User clicks "Request Item"]
       │
       └─→ ProductDetailScreen
            │
            └─→ [User confirms request]
                 │
                 └─→ Call Provider:
                      createRequestProvider.notifier
                           .createRequest(...)
                      │
                      └─→ Repository Layer:
                           RewardsRepository
                             .createRequest()
                                  │
                                  └─→ [Validate points]
                                       │
                                       └─→ Firestore.runTransaction():
                                            ├─ Read student doc
                                            ├─ Verify available_points >= required
                                            ├─ Deduct from available_points
                                            ├─ Add to locked_points
                                            ├─ Create request doc
                                            └─ Return requestId
                                                 │
                                                 └─→ Cloud Function Trigger:
                                                      onRewardRequestCreated()
                                                       │
                                                       ├─ Create notification
                                                       ├─ Log audit entry
                                                       └─ Return
                                                            │
                                                            └─→ UI Updated
                                                                 ✓ Request created!
                                                                 ✓ Points locked
                                                                 ✓ Parent notified
```

---

## 🎯 User Workflows

### Student Workflow
```
Start
  ↓
Browse Catalog
  ├─ Search for product
  ├─ Sort by price/rating
  └─ View product details
       ↓
    Select Product
       ├─ View price: ₹15,000
       ├─ View required points: 1,500
       ├─ Check own points: ✓ Have 2,000
       └─ Click "Request Item"
            ↓
         Parent Notification Sent
            ↓
         Wait for Parent Approval
            ├─ Check status: "Pending Approval"
            ├─ View my requests
            └─ Wait...
                 ↓
         [Parent Approves]
            ├─ Status: "Purchase In Progress"
            └─ Wait for delivery...
                 ↓
         Item Delivered!
            ├─ Get notification
            ├─ Click "Confirm Receipt"
            ├─ Verify checklist
            └─ Confirm button
                 ↓
         ✓ Complete!
            ├─ Status: "Completed"
            ├─ Points released: +1,450
            └─ Can redeem more items!
```

### Parent Workflow
```
Start
  ↓
Receive Notification
  "Child requested AirPods Pro (1,500 pts)"
       ↓
    Open Rewards Dashboard
       ├─ See "Pending Action"
       ├─ View request details
       │  ├─ Product: AirPods Pro
       │  ├─ Price: ₹15,000
       │  ├─ Points locked: 1,500
       │  └─ Requested at: timestamp
       └─ Decision time!
            │
       ┌────┴─────────┐
       │              │
    APPROVE        REJECT
       │              │
       ↓              ↓
    Confirm       Confirm
    Action        Action
       │              │
       ↓              ↓
    Notified      Points
    Store         Released
       │
       ↓
    Item Sent
       │
    ↓
    Notification:
    "Item delivered - confirm"
       │
       ↓
    Click Confirm
       │
       ├─ Delivery verified ✓
       ├─ Receipt checked ✓
       └─ Click Confirm Button
            ↓
         Complete!
            ├─ Points released to child
            └─ Can request more items
```

---

## 🔐 Security Model

```
User Roles
  │
  ├─ STUDENT
  │   ├─ Can: Browse catalog, create requests, view own requests
  │   ├─ Cannot: Approve requests, view other students' data
  │   └─ Firestore Rule: studentId == auth.uid
  │
  ├─ PARENT
  │   ├─ Can: View child requests, approve/reject, block students
  │   ├─ Cannot: View other families' data, create requests
  │   └─ Firestore Rule: childrenIds.contains(studentId)
  │
  └─ ADMIN
      ├─ Can: Everything (debug, override, manual entries)
      ├─ Cannot: (nothing - full access)
      └─ Firestore Rule: role == 'admin'

Request Flow Security
  │
  ├─ Create: Student creates → Function writes notification
  ├─ Update: Parent/Admin updates → Function logs audit
  ├─ Delete: Admin only → Function archives (soft delete)
  └─ Read: Student (own), Parent (children), Admin (all)

Points Security
  │
  ├─ Transactions: All point changes are atomic
  ├─ Audit: Every change logged with who/when/why
  ├─ Validation: State machine prevents invalid transitions
  └─ Recovery: Auto-expiry releases locked points
```

---

## 📱 Screen Navigation Map

```
App Router
│
├── /rewards/catalog
│   RewardsCatalogScreen
│   ├─ Search, Filter, Sort
│   └─ [Tap Product] → /rewards/product/:productId
│
├── /rewards/product/:productId
│   ProductDetailScreen
│   ├─ Full details, affiliate link
│   └─ [Request] → Cloud Function → /rewards/requests/student/:studentId
│
├── /rewards/requests/student/:studentId
│   StudentRequestsScreen
│   ├─ Status filter tabs
│   ├─ Request list with status
│   └─ [Tap Request] → /rewards/request/:requestId
│
├── /rewards/requests/parent/:parentId
│   ParentDashboardScreen
│   ├─ Pending / All toggle
│   ├─ Request list with actions
│   └─ [Tap Request] → /rewards/request/:requestId
│
└── /rewards/request/:requestId
    RequestDetailScreen
    ├─ Full timeline
    ├─ Points breakdown
    ├─ Audit history
    └─ Role-based action buttons
        ├─ Parent: Approve, Reject
        ├─ Student: Confirm Delivery
        └─ Both: View Details

Back Navigation
  └─ Uses GoRouter's back button stack
```

---

## ⚡ Performance Characteristics

```
Operation                    | Time Target | Actual
─────────────────────────────┼─────────────┼─────────────
Catalog Load                 | < 2s        | ~500-1000ms
Search Query                 | < 500ms     | ~200-400ms
Create Request (transaction) | < 2s        | ~1-1.5s
Point Update Stream          | < 1s        | ~200-500ms
Parent Approval              | < 1s        | ~800ms
Auto-Expiry Cron             | < 5s per 100 | Batch process
UI State Update (Riverpod)   | < 100ms     | ~50-100ms

Database Operations:
  • Read: 1 doc = ~10ms
  • Write: 1 doc = ~15ms
  • Transaction: ~30-50ms overhead
  • Query: Simple = ~50ms, Complex = ~100-200ms

Memory Usage:
  • Catalog cached: ~2-3 MB (30 products)
  • Per request data: ~50 KB
  • Providers snapshot: ~100 KB
  • Typical total: < 10 MB
```

---

## 🚀 Deployment & Integration Flow

```
Development
  │
  ├─ Create Firebase project
  ├─ Initialize Firestore
  ├─ Create Cloud Function triggers
  └─ Load dummy data (30 products)
       │
       ↓
Testing
  ├─ Run unit tests: flutter test
  ├─ Run integration tests: flutter drive
  ├─ Test Cloud Functions locally: firebase emulators
  └─ Manual QA on device
       │
       ↓
Staging
  ├─ Deploy to Firebase staging
  ├─ Test with real data
  ├─ Monitor logs and errors
  └─ User acceptance testing
       │
       ↓
Production
  ├─ Final checks
  ├─ Deploy Firestore rules
  ├─ Deploy Cloud Functions
  ├─ Load production products
  └─ Monitor performance
```

---

## 📊 Key Metrics & KPIs

```
User Adoption
  ├─ % of students using rewards
  ├─ Requests created per day
  ├─ Average points per student
  └─ Request completion rate

System Health
  ├─ Cloud Function error rate
  ├─ Firestore read/write quota
  ├─ API latency P95
  └─ Auto-expiry success rate

Business Metrics
  ├─ Average order value
  ├─ Request-to-completion time
  ├─ Parent approval rate
  └─ Student satisfaction score
```

---

## 🔗 Integration Checklist (Visual)

```
┌─ Code ────────────────────┐
│ ✓ Copy all 28 files       │
│ ✓ Update pubspec.yaml     │
│ ✓ Update main.dart router │
│ ✓ Wrap with ProviderScope │
└───────────────────────────┘

┌─ Firebase ────────────────┐
│ ✓ Deploy firestore.rules  │
│ ✓ Deploy functions (Node) │
│ ✓ Load dummy data         │
│ ✓ Configure auth roles    │
└───────────────────────────┘

┌─ Testing ─────────────────┐
│ ✓ Unit tests pass         │
│ ✓ Manual testing done     │
│ ✓ UAT approval            │
│ ✓ Performance acceptable  │
└───────────────────────────┘

┌─ Deployment ──────────────┐
│ ✓ Build release version   │
│ ✓ Upload to app stores    │
│ ✓ Monitor logs            │
│ ✓ Gather feedback         │
└───────────────────────────┘

READY TO LAUNCH ✅
```

---

**Visual Guide Complete** - All diagrams show the complete system architecture, data flows, workflows, and integration process.
