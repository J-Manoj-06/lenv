# Cloudflare Notification Integration Examples

## 🎯 How to Use

Import the service:
```dart
import 'package:new_reward/services/cloudflare_notification_service.dart';
```

---

## 📱 Example 1: Send Message with Notification

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:new_reward/services/cloudflare_notification_service.dart';

Future<void> sendMessageWithNotification({
  required String receiverId,
  required String text,
  String type = 'text',
}) async {
  final currentUserId = FirebaseAuth.instance.currentUser!.uid;

  // 1. Save message to Firestore
  final messageRef = await FirebaseFirestore.instance
      .collection('messages')
      .add({
    'senderId': currentUserId,
    'receiverId': receiverId,
    'text': text,
    'type': type,
    'timestamp': FieldValue.serverTimestamp(),
  });

  // 2. Send notification via Cloudflare Worker
  await CloudflareNotificationService.sendChatNotification(
    messageId: messageRef.id,
    senderId: currentUserId,
    receiverId: receiverId,
    text: text,
    messageType: type,
  );
}
```

---

## 📝 Example 2: Create Assignment with Notification

```dart
Future<void> createAssignmentWithNotification({
  required String title,
  required String description,
  required String classId,
}) async {
  final currentUserId = FirebaseAuth.instance.currentUser!.uid;

  // 1. Save assignment to Firestore
  final assignmentRef = await FirebaseFirestore.instance
      .collection('assignments')
      .add({
    'title': title,
    'description': description,
    'classId': classId,
    'createdBy': currentUserId,
    'timestamp': FieldValue.serverTimestamp(),
  });

  // 2. Send notification via Cloudflare Worker
  await CloudflareNotificationService.sendAssignmentNotification(
    assignmentId: assignmentRef.id,
    title: title,
    classId: classId,
    createdBy: currentUserId,
  );
}
```

---

## 📢 Example 3: Create Announcement with Notification

```dart
Future<void> createAnnouncementWithNotification({
  required String title,
  required String description,
  String targetRole = 'all',
}) async {
  final currentUserId = FirebaseAuth.instance.currentUser!.uid;

  // 1. Save announcement to Firestore
  final announcementRef = await FirebaseFirestore.instance
      .collection('announcements')
      .add({
    'title': title,
    'description': description,
    'targetRole': targetRole,
    'createdBy': currentUserId,
    'timestamp': FieldValue.serverTimestamp(),
  });

  // 2. Send notification via Cloudflare Worker
  await CloudflareNotificationService.sendAnnouncementNotification(
    announcementId: announcementRef.id,
    title: title,
    description: description,
    targetRole: targetRole,
    createdBy: currentUserId,
  );
}
```

---

## 🔧 Update Worker URL

In `lib/services/cloudflare_notification_service.dart`, update:

```dart
static const String _workerUrl = 'https://your-actual-worker.workers.dev/notify';
```

To find your worker URL:
1. Deploy worker: `./deploy-notification-worker.sh`
2. Copy URL from deployment output
3. Update _workerUrl constant

---

## 🔒 Add Authentication (Optional)

If you secured your worker with an API secret:

1. Set secret in worker:
```bash
wrangler secret put API_SECRET
```

2. Update Flutter service:
```dart
static const String? _apiSecret = 'your-api-secret';
```

---

## ✅ Complete Integration Flow

```
User Action (Send Message)
         ↓
Flutter App Logic
         ↓
Save to Firestore
         ↓
Call Cloudflare Worker
         ↓
Worker Sends FCM Notification
         ↓
Receiver Gets Notification
         ↓
Tap Notification
         ↓
App Opens Chat Screen
```

---

## 🧪 Test Integration

```dart
// Test notification
void testNotification() async {
  final success = await CloudflareNotificationService.sendChatNotification(
    messageId: 'test123',
    senderId: 'user1',
    receiverId: 'user2',
    text: 'Test notification from Flutter!',
    messageType: 'text',
  );
  
  print('Notification sent: $success');
}

// Check worker health
void checkWorker() async {
  final healthy = await CloudflareNotificationService.checkHealth();
  print('Worker is healthy: $healthy');
}
```

---

## 💡 Error Handling

Add try-catch in your UI:

```dart
try {
  await sendMessageWithNotification(
    receiverId: receiverId,
    text: text,
  );
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Message sent!')),
  );
} catch (e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Failed to send message: $e')),
  );
}
```

---

## 📊 Monitoring

Check Cloudflare Worker logs:
1. Go to Cloudflare Dashboard
2. Workers & Pages
3. Select notification-worker
4. View logs

You'll see:
- Successful notifications
- FCM tokens used
- Error messages (if any)

---

## 🎉 You're All Set!

Your notification system now uses:
- ✅ Flutter app for UI
- ✅ Cloudflare Worker for backend
- ✅ FCM for push notifications
- ✅ Firestore for storage

**No Firebase Blaze plan needed!** 🚀
