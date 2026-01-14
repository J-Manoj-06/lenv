# 🎯 Reward Approval System - Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        REWARD REQUEST LIFECYCLE                      │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────┐
│   STUDENT    │
│   DASHBOARD  │
└──────┬───────┘
       │
       ├─ Browse Rewards Catalog
       │
       ├─ Click "Request Reward"
       │
       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  CHECK: hasActivePendingRequest(studentId)                           │
├──────────────────────────────────────────────────────────────────────┤
│  IF TRUE:  ⏳ Show Warning → Block Request                           │
│  IF FALSE: ✅ Allow Request → Continue                               │
└──────────────┬───────────────────────────────────────────────────────┘
               │
               ▼
        ┌─────────────┐
        │   REQUEST   │──────────────────────────────────────┐
        │   CREATED   │  Status: PENDING                     │
        │             │  Expiry: Now + 21 days               │
        │  📦 Locked  │  Points: Locked from student         │
        └──────┬──────┘                                      │
               │                                              │
      ┌────────┴────────┐                                    │
      │   TIME PASSES   │                                    │
      └────────┬────────┘                                    │
               │                                              │
      ┌────────┴─────────────────────────────┐              │
      │   DAY 0-2: No warnings               │              │
      │   DAY 3-18: 🟠 "Pending X days"      │              │
      │   DAY 19-21: 🔴 "Expires in X days!" │              │
      │   DAY 21+: ⚠️ AUTO-EXPIRE            │              │
      └────────┬─────────────────────────────┘              │
               │                                              │
               ▼                                              │
┌──────────────────────────────────────────────────────────┐│
│              PARENT OPENS REWARDS SCREEN                  ││
│  → Auto-run: cancelExpiredRewardRequests()                ││
│  → Check all pending > 21 days                            ││
└──────────────┬───────────────────────────────────────────┘│
               │                                              │
          ┌────┴──────┐                                      │
          │  EXPIRED? │                                      │
          └────┬──────┘                                      │
               │                                              │
        ┌──────┴──────┐                                      │
        │     YES     │                                      │
        ▼             ▼                                      │
  ┌─────────┐   ┌─────────────┐                            │
  │ CANCEL  │   │   NO: VIEW  │                            │
  │ REQUEST │   │   PENDING   │                            │
  └────┬────┘   └──────┬──────┘                            │
       │               │                                     │
       │               ▼                                     │
       │    ┌──────────────────┐                            │
       │    │  PARENT CLICKS   │                            │
       │    │  "APPROVE"       │                            │
       │    └────────┬─────────┘                            │
       │             │                                       │
       │             ▼                                       │
       │    ┌─────────────────────────────────────┐        │
       │    │     CHOOSE PURCHASE METHOD:         │        │
       │    ├─────────────────────────────────────┤        │
       │    │  🛒 Amazon Affiliate                │        │
       │    │  🏪 Manual Purchase                 │        │
       │    └─────────┬──────────────┬────────────┘        │
       │              │              │                      │
       │      ┌───────┴──┐      ┌───┴────────┐            │
       │      │  AMAZON  │      │   MANUAL   │            │
       │      └─────┬────┘      └─────┬──────┘            │
       │            │                  │                    │
       │            ▼                  ▼                    │
       │  ┌──────────────────┐  ┌─────────────────┐      │
       │  │ Mark approved    │  │ Show price input│      │
       │  │ purchase_mode:   │  │ Validate > 0    │      │
       │  │ "amazon"         │  │ Save manual_price│     │
       │  └────────┬─────────┘  └────────┬────────┘      │
       │           │                     │                 │
       │           └──────────┬──────────┘                │
       │                      ▼                            │
       │            ┌──────────────────┐                  │
       │            │  STATUS: APPROVED│                  │
       │            │  📦 Points stay  │                  │
       │            │     locked       │                  │
       │            └────────┬─────────┘                  │
       │                     │                             │
       │                     ▼                             │
       │          ┌─────────────────────┐                │
       │          │  STUDENT NOTIFIED   │                │
       │          │  Can request again  │                │
       │          └─────────────────────┘                │
       │                                                   │
       ▼                                                   │
┌──────────────────────────────────────────┐            │
│  AUTO-EXPIRED: STATUS CHANGE             │            │
├──────────────────────────────────────────┤            │
│  • Status → expiredOrAutoResolved        │            │
│  • Points unlocked and returned          │            │
│  • Audit: "system/cancelled/EXPIRED"     │            │
│  • Student can request new reward        │            │
└──────────────────────────────────────────┘            │
                                                         │
                                                         │
┌──────────────────────────────────────────┐            │
│  PARENT REJECTS                          │◄───────────┘
├──────────────────────────────────────────┤
│  • Status → cancelled                    │
│  • Points unlocked and returned          │
│  • Audit: "parent_id/cancelled"          │
│  • Student can request new reward        │
└──────────────────────────────────────────┘
```

---

## 🔄 State Transitions

```
┌─────────────────────────────────────────────────────────────────┐
│                        STATUS FLOW                               │
└─────────────────────────────────────────────────────────────────┘

        CREATE REQUEST
              │
              ▼
    ┌──────────────────┐
    │     PENDING      │ ← Initial State
    │ (Day 0)          │
    └──────────────────┘
              │
              │ (3 days)
              ▼
    ┌──────────────────┐
    │     PENDING      │ + 🟠 Reminder Badge
    │ (Day 3)          │
    └──────────────────┘
              │
              │ (18 days)
              ▼
    ┌──────────────────┐
    │     PENDING      │ + 🔴 Expiry Warning
    │ (Day 18)         │
    └──────────────────┘
              │
              │
      ┌───────┴────────────────┐
      │                        │
      │ (21 days)              │ (Parent Action)
      ▼                        ▼
┌───────────┐         ┌─────────────────┐
│  EXPIRED  │         │    APPROVED     │
│ (Auto)    │         │ (Amazon/Manual) │
└───────────┘         └─────────────────┘
      │                        │
      │                        │
      ▼                        ▼
  Points                   Points stay
 Returned                    locked
```

---

## 📊 Points Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      POINTS MANAGEMENT                           │
└─────────────────────────────────────────────────────────────────┘

Student Initial State:
┌──────────────────────────────────────┐
│  Available: 1000 points              │
│  Locked: 0 points                    │
└──────────────────────────────────────┘
              │
              │ Student requests reward (500 points)
              ▼
┌──────────────────────────────────────┐
│  Available: 500 points  (1000-500)   │
│  Locked: 500 points     (+500)       │
│  Status: PENDING                     │
└──────────────────────────────────────┘
              │
        ┌─────┴──────┐
        │            │
        │ APPROVED   │ EXPIRED/CANCELLED
        ▼            ▼
┌──────────────┐  ┌──────────────────────┐
│ Points stay  │  │ Available: 1000      │
│ locked until │  │ Locked: 0            │
│ delivered    │  │ (Points restored)    │
└──────────────┘  └──────────────────────┘
```

---

## 🎨 UI Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    PARENT APPROVAL CARD                          │
├─────────────────────────────────────────────────────────────────┤
│  Gaming Mouse 🏷️ PENDING                                        │
│  Requested on Dec 19, 2024                                       │
│  ⏰ Pending for 4 days                    ← Time Warning        │
│  ─────────────────────────────────────────                      │
│  🎁 Points Required: 500 points                                  │
│  🛍️ Price: ₹1200                                                │
│  ─────────────────────────────────────────                      │
│  [  ✖ Reject  ] [  ✓ Approve  ]           ← Action Buttons    │
└─────────────────────────────────────────────────────────────────┘
                    │
                    │ Click "Approve"
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│           Choose Purchase Method                                 │
├─────────────────────────────────────────────────────────────────┤
│  How would you like to fulfill "Gaming Mouse"?                   │
│                                                                   │
│  ┌──────────────────────────────────────────────────────┐      │
│  │  🛒  Amazon Affiliate                    →            │      │
│  │      Order via Amazon link                            │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                                   │
│  ┌──────────────────────────────────────────────────────┐      │
│  │  🏪  Manual Purchase                     →            │      │
│  │      Buy locally or from other store                  │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                                   │
│                                    [  Cancel  ]                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔔 Reminder System

```
┌─────────────────────────────────────────────────────────────────┐
│                    REMINDER TIMELINE                             │
└─────────────────────────────────────────────────────────────────┘

Day 0:  Request Created
        ├─ No badge
        └─ No reminder

Day 1-2: Waiting
        ├─ No badge
        └─ No reminder

Day 3:  First Reminder Trigger
        ├─ 🟠 Badge: "Pending for 3 days"
        ├─ Set: lastReminderSentAt = now
        └─ (Optional: Send notification)

Day 4-5: Cool-down
        ├─ 🟠 Badge: "Pending for X days"
        └─ No new reminder

Day 6:  Second Reminder
        ├─ 🟠 Badge: "Pending for 6 days"
        ├─ Update: lastReminderSentAt = now
        └─ (Optional: Send notification)

Day 18: Expiry Warning
        ├─ 🔴 Badge: "Expires in 3 days!"
        └─ Urgent state

Day 21: Auto-Expire
        ├─ Status → expiredOrAutoResolved
        ├─ Points returned
        └─ Request removed from pending
```

---

## ✅ Decision Tree

```
Student Clicks "Request Reward"
        │
        ▼
   ┌────────────┐
   │  Student   │
   │  signed in?│
   └─────┬──────┘
         │ YES
         ▼
   ┌─────────────────┐
   │ Has pending     │───YES──→ 🚫 Block + Show Warning
   │ request?        │
   └─────┬───────────┘
         │ NO
         ▼
   ┌─────────────────┐
   │ Enough points?  │───NO───→ 🚫 Show "Need X more points"
   └─────┬───────────┘
         │ YES
         ▼
   ┌─────────────────┐
   │ Create request  │
   │ Lock points     │
   │ Notify parent   │
   └─────────────────┘
```

---

**All flows implemented and tested!** ✅
