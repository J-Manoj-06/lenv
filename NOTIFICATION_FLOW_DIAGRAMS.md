# Lenv Notification System - Flow Diagrams

## 1. Chat Notification Flow

```
┌─────────────┐
│  User A     │
│  Sends      │
│  Message    │
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Firestore: messages collection      │
│  onCreate trigger                    │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Cloud Function:                     │
│  sendChatNotification                │
│  1. Get receiver ID                  │
│  2. Fetch FCM token                  │
│  3. Send push notification           │
│  4. Save to notifications collection │
└──────┬───────────────────────────────┘
       │
       ├──────────────────┬────────────────┐
       ▼                  ▼                ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Firebase     │  │ Firestore    │  │ User B's     │
│ Cloud        │  │ notifications│  │ Device       │
│ Messaging    │  │ collection   │  │              │
└──────┬───────┘  └──────────────┘  └──────┬───────┘
       │                                    │
       └────────────────┬───────────────────┘
                        ▼
                ┌──────────────────┐
                │  User B          │
                │  Receives        │
                │  Notification    │
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │  Tap             │
                │  Notification    │
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │  App Opens       │
                │  Chat Screen     │
                │  with User A     │
                └──────────────────┘
```

---

## 2. Assignment Notification Flow

```
┌─────────────┐
│  Teacher    │
│  Creates    │
│  Assignment │
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Firestore: assignments collection   │
│  onCreate trigger                    │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Cloud Function:                     │
│  sendAssignmentNotification          │
│  1. Get class ID                     │
│  2. Fetch all students in class      │
│  3. Get FCM tokens                   │
│  4. Send notifications (batch)       │
│  5. Save to notifications collection │
└──────┬───────────────────────────────┘
       │
       ├──────────────────┬──────────────────┐
       ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Student 1    │  │ Student 2    │  │ Student N    │
│ Device       │  │ Device       │  │ Device       │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                  │                  │
       └──────────────────┼──────────────────┘
                          ▼
                  ┌──────────────────┐
                  │  All Students    │
                  │  Receive         │
                  │  Notification    │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  Tap             │
                  │  Notification    │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  App Opens       │
                  │  Assignment      │
                  │  Details         │
                  └──────────────────┘
```

---

## 3. Announcement Notification Flow

```
┌─────────────┐
│  Admin      │
│  Creates    │
│  Announcement│
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Firestore: announcements collection │
│  onCreate trigger                    │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Cloud Function:                     │
│  sendAnnouncementNotification        │
│  1. Get target role (or all)         │
│  2. Fetch all users by role          │
│  3. Get FCM tokens                   │
│  4. Send notifications (batch)       │
│  5. Save to notifications collection │
└──────┬───────────────────────────────┘
       │
       ├────────────┬────────────┬────────────┐
       ▼            ▼            ▼            ▼
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ Students │  │ Parents  │  │ Teachers │  │ All Users│
│          │  │          │  │          │  │          │
└────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │             │
     └─────────────┴─────────────┴─────────────┘
                           ▼
                  ┌──────────────────┐
                  │  All Targeted    │
                  │  Users Receive   │
                  │  Notification    │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  Tap             │
                  │  Notification    │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  App Opens       │
                  │  Announcement    │
                  │  Details         │
                  └──────────────────┘
```

---

## 4. FCM Token Management Flow

```
┌─────────────┐
│  User       │
│  Logs In    │
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────────┐
│  NotificationService                 │
│  initialize()                        │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Request Notification Permission     │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Get FCM Token                       │
│  FirebaseMessaging.getToken()        │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Save to Firestore                   │
│  users/{userId}/fcmToken             │
└──────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Listen for Token Refresh            │
│  onTokenRefresh.listen()             │
└──────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Token Updated                       │
│  Auto-save to Firestore              │
└──────────────────────────────────────┘
```

---

## 5. Notification State Flow

```
                    ┌──────────────────┐
                    │  Notification    │
                    │  Received        │
                    └────────┬─────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
           ▼                 ▼                 ▼
    ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
    │ Foreground  │   │ Background  │   │ Terminated  │
    │ App active  │   │ App in      │   │ App not     │
    │             │   │ background  │   │ running     │
    └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
           │                 │                 │
           ▼                 ▼                 ▼
    ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
    │ Show local  │   │ Show system │   │ Show system │
    │ notification│   │ notification│   │ notification│
    └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
           │                 │                 │
           └─────────────────┼─────────────────┘
                             ▼
                    ┌──────────────────┐
                    │  Save to         │
                    │  Firestore       │
                    │  notifications   │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │  User Taps       │
                    │  Notification    │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │  Navigate to     │
                    │  Appropriate     │
                    │  Screen          │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │  Mark as Read    │
                    │  isRead: true    │
                    └──────────────────┘
```

---

## 6. Notification Screen Flow

```
┌─────────────┐
│  User Taps  │
│  Bell Icon  │
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────────┐
│  NotificationsScreen                 │
│  StreamBuilder                       │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Query Firestore                     │
│  WHERE userId = current user         │
│  ORDER BY timestamp DESC             │
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Display Notifications               │
│  • Chat (blue)                       │
│  • Assignment (orange)               │
│  • Announcement (purple)             │
└──────┬───────────────────────────────┘
       │
       ├────────────────┬────────────────┐
       ▼                ▼                ▼
┌──────────┐    ┌──────────────┐  ┌──────────────┐
│  Tap     │    │  Swipe Left  │  │  Menu        │
│  Card    │    │  to Delete   │  │  Actions     │
└────┬─────┘    └──────┬───────┘  └──────┬───────┘
     │                 │                 │
     │                 ▼                 ▼
     │          ┌──────────────┐  ┌──────────────┐
     │          │  Delete      │  │ Mark All     │
     │          │  Notification│  │ as Read      │
     │          └──────────────┘  │ or           │
     │                            │ Clear All    │
     │                            └──────────────┘
     ▼
┌──────────────────────────────────────┐
│  Navigate Based on Type              │
│  • Chat → Chat Screen                │
│  • Assignment → Assignment Screen    │
│  • Announcement → Announcement Screen│
└──────┬───────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Mark as Read                        │
│  Update isRead: true in Firestore    │
└──────────────────────────────────────┘
```

---

## 7. System Component Interactions

```
┌────────────────────────────────────────────────────────┐
│                    Flutter App                          │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  NotificationService                              │  │
│  │  • Initialize FCM                                 │  │
│  │  • Handle foreground/background/terminated        │  │
│  │  • Manage FCM token                               │  │
│  │  • Provide streams (unread count, tap events)     │  │
│  └────────────────────┬─────────────────────────────┘  │
│                       │                                 │
│  ┌────────────────────┴─────────────────────────────┐  │
│  │  UI Layer                                         │  │
│  │  • NotificationsScreen                            │  │
│  │  • NotificationCard                               │  │
│  │  • Notification Bell Badge                        │  │
│  └────────────────────┬─────────────────────────────┘  │
└─────────────────────────┬───────────────────────────────┘
                          │
         ┌────────────────┼────────────────┐
         ▼                ▼                ▼
┌─────────────┐  ┌──────────────┐  ┌──────────────┐
│  Firebase   │  │  Firebase    │  │  Firebase    │
│  Cloud      │  │  Firestore   │  │  Cloud       │
│  Messaging  │  │              │  │  Functions   │
└─────────────┘  └──────────────┘  └──────────────┘
       │                │                   │
       │                │                   │
       └────────────────┼───────────────────┘
                        │
         ┌──────────────┴──────────────┐
         ▼                             ▼
┌──────────────────┐          ┌──────────────────┐
│  notifications   │          │  users           │
│  collection      │          │  collection      │
│  • userId        │          │  • fcmToken      │
│  • title         │          │  • name          │
│  • body          │          │  • role          │
│  • type          │          └──────────────────┘
│  • referenceId   │
│  • isRead        │
│  • timestamp     │
└──────────────────┘
```

---

## 8. Data Flow Sequence

```
1. EVENT TRIGGER
   └─> New document created in Firestore
       (messages, assignments, or announcements)

2. CLOUD FUNCTION EXECUTION
   └─> Firestore trigger activates
       └─> Function reads event data
           └─> Queries for recipient user(s)
               └─> Retrieves FCM token(s)

3. NOTIFICATION SENDING
   └─> Constructs notification payload
       └─> Sends via Firebase Cloud Messaging
           └─> Saves to notifications collection

4. DEVICE RECEIPT
   └─> FCM delivers to device
       └─> App state determines display method
           ├─> Foreground: flutter_local_notifications
           ├─> Background: System notification
           └─> Terminated: System notification

5. USER INTERACTION
   └─> User sees notification
       └─> Taps notification
           └─> App opens/comes to foreground
               └─> Navigation handler processes data
                   └─> Opens appropriate screen
                       └─> Marks notification as read

6. FIRESTORE UPDATE
   └─> Notification document updated
       └─> isRead = true
           └─> UI updates via StreamBuilder
               └─> Unread count decreases
```

---

## 9. Error Handling Flow

```
┌─────────────────────┐
│  Notification       │
│  Attempt            │
└──────┬──────────────┘
       │
       ▼
┌──────────────────────────────────┐
│  Check User Exists               │
└──────┬───────────────────────────┘
       │
       ├─NO─> Log Error → Exit
       │
       ▼ YES
┌──────────────────────────────────┐
│  Check FCM Token Exists          │
└──────┬───────────────────────────┘
       │
       ├─NO─> Log "No token" → Exit
       │
       ▼ YES
┌──────────────────────────────────┐
│  Attempt Send Notification       │
└──────┬───────────────────────────┘
       │
       ├─ERROR─> Log Error
       │         │
       │         ├─> Invalid Token → Remove from DB
       │         ├─> Service Error → Retry
       │         └─> Unknown → Log & Alert
       │
       ▼ SUCCESS
┌──────────────────────────────────┐
│  Save to Firestore               │
└──────┬───────────────────────────┘
       │
       ├─ERROR─> Log Error
       │         (notification sent but not saved)
       │
       ▼ SUCCESS
┌──────────────────────────────────┐
│  Complete                        │
└──────────────────────────────────┘
```

---

## 10. Cleanup Job Flow

```
┌─────────────────────┐
│  Daily at 2 AM      │
│  Scheduled Trigger  │
└──────┬──────────────┘
       │
       ▼
┌──────────────────────────────────┐
│  cleanupOldNotifications         │
│  Cloud Function                  │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│  Calculate Date                  │
│  30 Days Ago                     │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│  Query Firestore                 │
│  WHERE isRead = true             │
│  AND timestamp < 30 days ago     │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│  Batch Delete                    │
│  (up to 500 at a time)           │
└──────┬───────────────────────────┘
       │
       ▼
┌──────────────────────────────────┐
│  Log Results                     │
│  • Number deleted                │
│  • Timestamp                     │
└──────────────────────────────────┘
```

---

## Legend

```
┌─────────┐
│  Box    │  = Component / Step
└─────────┘

    │
    ▼         = Flow Direction

    ├──>      = Branch / Alternative Path

    └──>      = Merge / Continue

```

---

These diagrams show the complete flow of the Lenv notification system from trigger to user interaction.
