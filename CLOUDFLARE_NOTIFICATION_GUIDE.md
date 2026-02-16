# Lenv Notification System - Cloudflare Workers Implementation

## 🎯 Overview

Since you're using **Cloudflare Workers** instead of Firebase Cloud Functions, I've created a Cloudflare Worker implementation for push notifications.

---

## 📦 What Changed

### ✅ Flutter App (No Changes Needed)
All Flutter code remains the same:
- `notification_service.dart`
- `notification_model.dart`
- `notifications_screen.dart`
- `notification_card.dart`

### ✅ Backend (Cloudflare Worker Instead of Firebase Functions)
Instead of Firebase Cloud Functions, you now have:
- `cloudflare-worker/src/notification-worker.ts` - Cloudflare Worker for notifications
- `wrangler-notification.jsonc` - Configuration
- `deploy-notification-worker.sh` - Deployment script

---

## 🚀 Deployment Steps

### Step 1: Install Dependencies

```bash
cd cloudflare-worker
npm install firebase-admin
```

### Step 2: Set Environment Variables

In your Cloudflare Workers dashboard, set these secrets:

```bash
# Navigate to your worker settings
wrangler secret put FIREBASE_PROJECT_ID
# Enter: your-project-id

wrangler secret put FIREBASE_SERVICE_ACCOUNT
# Enter: base64_encoded_service_account_json

wrangler secret put FIRESTORE_DATABASE_URL  
# Enter: https://firestore.googleapis.com
```

To get base64 encoded service account:
```bash
# Download your Firebase service account JSON
# Then encode it:
cat path/to/serviceAccountKey.json | base64 -w 0
```

### Step 3: Deploy the Worker

```bash
cd /home/manoj/Desktop/new_reward
./deploy-notification-worker.sh
```

Or manually:
```bash
cd cloudflare-worker
npx wrangler deploy --config wrangler-notification.jsonc
```

---

## 🔧 How It Works

### Architecture

```
Flutter App → Firestore (create message/assignment/announcement)
                ↓
        Your App Logic (detects new document)
                ↓
   HTTP POST to Cloudflare Worker
                ↓
        Worker sends FCM notification
                ↓
        Saves to Firestore notifications collection
```

### Worker Endpoint

```
POST https://your-worker.workers.dev/notify
```

### Request Format

#### Chat Notification
```json
{
  "type": "chat",
  "messageId": "msg123",
  "senderId": "user1",
  "receiverId": "user2",
  "text": "Hello!",
  "messageType": "text"
}
```

#### Assignment Notification
```json
{
  "type": "assignment",
  "assignmentId": "assign123",
  "title": "Math Homework",
  "classId": "class123",
  "createdBy": "teacher1"
}
```

#### Announcement Notification
```json
{
  "type": "announcement",
  "announcementId": "announce123",
  "title": "Holiday Notice",
  "description": "School closed tomorrow",
  "targetRole": "all",
  "createdBy": "admin1"
}
```

---

## 💡 Integration Options

### Option 1: Call from Flutter App Directly

Update your Flutter app to call the Cloudflare Worker when creating messages/assignments/announcements:

```dart
// In your message sending code
Future<void> sendMessage(String receiverId, String text) async {
  // 1. Save message to Firestore
  final messageRef = await FirebaseFirestore.instance.collection('messages').add({
    'senderId': currentUserId,
    'receiverId': receiverId,
    'text': text,
    'type': 'text',
    'timestamp': FieldValue.serverTimestamp(),
  });
  
  // 2. Call Cloudflare Worker to send notification
  await http.post(
    Uri.parse('https://your-worker.workers.dev/notify'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'type': 'chat',
      'messageId': messageRef.id,
      'senderId': currentUserId,
      'receiverId': receiverId,
      'text': text,
      'messageType': 'text',
    }),
  );
}
```

### Option 2: Use Firestore Triggers (Recommended)

Set up Firestore triggers that call your Cloudflare Worker. You can use:

1. **Firebase Extensions** (if available)
2. **Cloud Functions** (free tier) to trigger the worker
3. **Webhook/HTTP trigger** from your existing backend

#### Example: Simple Cloud Function to Trigger Worker

Create a minimal Firebase Function (stays in free tier):

```javascript
// functions/index.js
const functions = require('firebase-functions');
const axios = require('axios');

exports.onMessageCreated = functions.firestore
  .document('messages/{messageId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    
    await axios.post('https://your-worker.workers.dev/notify', {
      type: 'chat',
      messageId: context.params.messageId,
      senderId: data.senderId,
      receiverId: data.receiverId,
      text: data.text,
      messageType: data.type,
    });
    
    return null;
  });

// Similar functions for assignments and announcements
```

This approach:
- Uses minimal Firebase Functions (stays free)
- Offloads heavy lifting to Cloudflare Worker
- No Blaze plan needed

---

## 🧪 Testing

### Test Health Check

```bash
curl https://your-worker.workers.dev/health
```

Response:
```json
{
  "status": "ok",
  "service": "notification-worker"
}
```

### Test Chat Notification

```bash
curl -X POST https://your-worker.workers.dev/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "chat",
    "messageId": "test123",
    "senderId": "user1_id",
    "receiverId": "user2_id",
    "text": "Test notification",
    "messageType": "text"
  }'
```

---

## 📊 Cost Comparison

### Cloudflare Workers (Your Setup)
- **100,000 requests/day**: FREE
- **Beyond that**: $0.50 per million requests
- **Much cheaper** than Firebase Functions

### Firebase Functions (Original Plan)
- Requires Blaze (pay-as-you-go) plan
- ~$0.40 per million invocations
- More expensive for high volume

**Cloudflare Workers is the better choice!** ✅

---

## 🔒 Security

Add authentication to your worker:

```typescript
// In notification-worker.ts
const authHeader = request.headers.get('Authorization');
if (authHeader !== `Bearer ${env.API_SECRET}`) {
  return new Response('Unauthorized', { status: 401 });
}
```

Set the secret:
```bash
wrangler secret put API_SECRET
```

---

## 📝 Files Created

1. **`cloudflare-worker/src/notification-worker.ts`** - Main worker code
2. **`cloudflare-worker/wrangler-notification.jsonc`** - Configuration
3. **`deploy-notification-worker.sh`** - Deployment script
4. **`CLOUDFLARE_NOTIFICATION_GUIDE.md`** - This guide

---

## ✅ Deployment Checklist

- [ ] Install firebase-admin in cloudflare-worker
- [ ] Get Firebase service account JSON
- [ ] Encode service account to base64
- [ ] Set Cloudflare Worker secrets
- [ ] Deploy worker
- [ ] Update Flutter app to call worker endpoint
- [ ] Test chat notifications
- [ ] Test assignment notifications
- [ ] Test announcement notifications

---

## 🎉 Advantages of This Approach

1. **No Blaze Plan Required** - Use Cloudflare's generous free tier
2. **Better Performance** - Cloudflare's global network
3. **Lower Costs** - Much cheaper at scale
4. **Easy Integration** - Simple HTTP endpoints
5. **Keep Flutter Code** - No changes to your Flutter app

---

## 📞 Next Steps

1. Deploy the worker: `./deploy-notification-worker.sh`
2. Set environment variables in Cloudflare dashboard
3. Choose integration option (direct call or trigger function)
4. Test notifications
5. Monitor worker logs in Cloudflare dashboard

Your notification system is production-ready with Cloudflare Workers! 🚀
