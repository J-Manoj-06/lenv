# Notification System Testing Guide

## Prerequisites

Before testing, ensure:
- ✅ Cloudflare Worker deployed: https://lenv-notification-worker.giridharannj.workers.dev
- ✅ Flutter app has notification service initialized
- ⏳ Environment variables set (see below)

## Quick Setup: Environment Variables

### Option 1: Using Wrangler CLI (Recommended)

```bash
cd cloudflare-worker

# 1. Set basic variables
echo "lenv-cb08e" | wrangler secret put FIREBASE_PROJECT_ID
echo "https://firestore.googleapis.com" | wrangler secret put FIRESTORE_DATABASE_URL

# 2. Download service account from Firebase Console:
#    https://console.firebase.google.com/project/lenv-cb08e/settings/serviceaccounts/adminsdk
#    Click "Generate new private key" → Save as firebase-service-account.json

# 3. Set service account (base64 encoded)
cat firebase-service-account.json | base64 -w 0 | wrangler secret put FIREBASE_SERVICE_ACCOUNT

cd ..
```

### Option 2: Using Cloudflare Dashboard

1. Go to: https://dash.cloudflare.com/
2. Navigate to: **Workers & Pages** → **lenv-notification-worker** → **Settings** → **Variables**
3. Add these **encrypted** secrets:
   - `FIREBASE_PROJECT_ID` = `lenv-cb08e`
   - `FIRESTORE_DATABASE_URL` = `https://firestore.googleapis.com`
   - `FIREBASE_SERVICE_ACCOUNT` = [base64 encoded service account JSON]

---

## Testing Methods

### Method 1: Quick Test with Script

```bash
# Run automated tests
./test-notifications.sh
```

This will test:
- ✅ Health check endpoint
- ✅ Chat notification
- ✅ Assignment notification
- ✅ Announcement notification

### Method 2: Manual API Testing

#### Health Check
```bash
curl https://lenv-notification-worker.giridharannj.workers.dev/health
```

Expected response:
```json
{
  "status": "ok",
  "timestamp": "2026-02-16T...",
  "firebase": "initialized"
}
```

#### Send Chat Notification
```bash
curl -X POST https://lenv-notification-worker.giridharannj.workers.dev/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "chat",
    "userId": "YOUR_USER_ID",
    "title": "New Message",
    "body": "You have a new message!",
    "data": {
      "messageId": "msg123",
      "chatId": "chat456",
      "senderId": "sender789"
    }
  }'
```

#### Send Assignment Notification
```bash
curl -X POST https://lenv-notification-worker.giridharannj.workers.dev/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "assignment",
    "userId": "YOUR_USER_ID",
    "title": "New Assignment",
    "body": "Math homework due tomorrow",
    "data": {
      "assignmentId": "assign123",
      "subjectId": "math101",
      "dueDate": "2026-02-17T23:59:59Z"
    }
  }'
```

#### Send Announcement Notification
```bash
curl -X POST https://lenv-notification-worker.giridharannj.workers.dev/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "announcement",
    "userId": "YOUR_USER_ID",
    "title": "School Announcement",
    "body": "Holiday next week!",
    "data": {
      "announcementId": "announce123",
      "priority": "high"
    }
  }'
```

### Method 3: Test from Flutter App

#### Get Your FCM Token (for testing)
Add this temporarily in your Flutter app:

```dart
// In main.dart or any screen
import 'package:new_reward/services/notification_service.dart';

// Get token
final token = await NotificationService().getToken();
print('FCM Token: $token');
```

#### Get Your User ID
```dart
final userId = FirebaseAuth.instance.currentUser?.uid;
print('User ID: $userId');
```

#### Send a Test Notification from Chat
```dart
import 'package:new_reward/services/cloudflare_notification_service.dart';

// When sending a chat message
await CloudflareNotificationService.sendChatNotification(
  messageId: messageRef.id,
  senderId: currentUserId,
  receiverId: receiverUserId,
  text: messageText,
  messageType: 'text',
);
```

---

## Verification Steps

### 1. Check Firestore
Open Firebase Console → Firestore Database → `notifications` collection
- Should see new notification documents
- Check fields: `userId`, `type`, `title`, `body`, `data`, `isRead`, `timestamp`

### 2. Check Device Notifications
- **Foreground**: Should show local notification banner
- **Background**: Should show FCM push notification
- **Terminated**: Should show FCM push notification

### 3. Check App Notification Screen
Open the app → Navigate to Notifications screen
- Should see list of notifications
- Unread badge should show count
- Tap notification → Should navigate to relevant screen
- Swipe to delete → Should remove notification

### 4. Check Worker Logs (Cloudflare Dashboard)
Go to: Workers & Pages → lenv-notification-worker → Logs
- View real-time logs
- Check for errors
- Monitor request/response

---

## Testing Checklist

### Basic Functionality
- [ ] Health check endpoint responds
- [ ] Can send chat notification
- [ ] Can send assignment notification
- [ ] Can send announcement notification
- [ ] Notifications saved to Firestore
- [ ] Notifications appear in app

### Notification Delivery
- [ ] Foreground notification shows
- [ ] Background notification shows
- [ ] Terminated state notification shows
- [ ] Notification tap opens app
- [ ] Notification tap navigates to correct screen

### App Features
- [ ] Notification list shows all notifications
- [ ] Unread count is accurate
- [ ] Mark as read works
- [ ] Delete notification works
- [ ] Mark all as read works
- [ ] Pull to refresh works
- [ ] Real-time updates work

### Edge Cases
- [ ] User has no FCM token (graceful handling)
- [ ] Invalid user ID (error handling)
- [ ] Missing required fields (validation)
- [ ] Multiple notifications stack properly
- [ ] Old notifications display correctly

---

## Troubleshooting

### Worker returns 500 error
**Check:**
- Environment variables are set correctly
- Service account JSON is valid and properly encoded
- Cloudflare Worker logs for detailed error

**Fix:**
```bash
# Re-verify environment variables
cd cloudflare-worker
wrangler secret list
```

### Notifications not appearing on device
**Check:**
- FCM token is saved in Firestore (`users/{userId}/fcmToken`)
- Notification permissions granted on device
- Google Services JSON is in android/app/
- App is properly connected to Firebase

**Debug:**
```dart
// Check token
final token = await NotificationService().getToken();
print('Token: $token');

// Check permissions
final settings = await FirebaseMessaging.instance.requestPermission();
print('Permission: ${settings.authorizationStatus}');
```

### Notifications saved to Firestore but not delivered
**Check:**
- Worker has correct service account with FCM permissions
- FCM token is valid (not expired)
- Device has internet connection
- Firebase Cloud Messaging is enabled in Firebase Console

### Navigation not working on tap
**Check:**
- `data` field contains required IDs (messageId, assignmentId, etc.)
- Navigation routes are registered in app
- Data is properly parsed in `_handleNotificationTap()`

---

## Performance Testing

### Load Test (Optional)
```bash
# Send 10 notifications
for i in {1..10}; do
  curl -X POST https://lenv-notification-worker.giridharannj.workers.dev/notify \
    -H 'Content-Type: application/json' \
    -d "{\"type\":\"chat\",\"userId\":\"test-user\",\"title\":\"Test $i\",\"body\":\"Message $i\"}"
  sleep 0.5
done
```

### Monitor Worker Performance
Go to: Cloudflare Dashboard → Workers → lenv-notification-worker → Analytics
- Requests per second
- Errors
- Duration (p50, p99)
- Success rate

---

## Next Steps After Testing

Once testing is complete:

1. **Remove test code** (print statements, test buttons)
2. **Update security rules** (restrict who can read/write notifications)
3. **Set up monitoring** (error tracking, analytics)
4. **Document for your team** (how to trigger notifications)
5. **Test on real devices** (different Android versions)

---

## Support

If you encounter issues:

1. Check Cloudflare Worker logs
2. Check Firebase Console logs
3. Check Flutter app logs (`flutter logs`)
4. Review [NOTIFICATION_SYSTEM_DOCUMENTATION.md](NOTIFICATION_SYSTEM_DOCUMENTATION.md)

## Quick Reference

- **Worker URL**: https://lenv-notification-worker.giridharannj.workers.dev
- **Project ID**: lenv-cb08e
- **Flutter Service**: `lib/services/cloudflare_notification_service.dart`
- **Notification Screen**: `lib/screens/notifications/notifications_screen.dart`
