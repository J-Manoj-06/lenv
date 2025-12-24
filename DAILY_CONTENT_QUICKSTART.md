# 🚀 Quick Start - Daily Content System

## Deploy in 5 Minutes

### 1️⃣ Build Worker
```bash
cd cloudflare-worker
npm install --save-dev @cloudflare/workers-types typescript
tsc --project tsconfig-daily.json
```

### 2️⃣ Get Firebase Service Account
1. [Firebase Console](https://console.firebase.google.com/) → Your Project
2. **Settings** → **Service Accounts** → **Generate New Private Key**
3. Download JSON → Copy **entire content** as single line

### 3️⃣ Set Secret
```bash
wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler-daily-content.jsonc
# Paste JSON, press Enter
```

### 4️⃣ Deploy
```bash
wrangler deploy --config wrangler-daily-content.jsonc
firebase deploy --only firestore:rules
```

### 5️⃣ Test
```bash
# Manual trigger
curl -X POST https://daily-content-worker.<account>.workers.dev

# Check Firestore
# daily_content/2025-12-18 should exist
```

### 6️⃣ Run Flutter App
```bash
flutter pub get
flutter run
# Test: Open AI Chat → Click "Today's Quote" / "Daily Fact"
```

---

## ✅ What You Get

- **Cost**: FREE (Cloudflare Workers - no Firebase Functions)
- **API Calls**: 99.7% reduction (900/day → 3/day)
- **Speed**: 10-30x faster (Firestore cache vs HTTP fetch)
- **Schedule**: Auto-runs daily at 2:00 AM IST
- **Reliability**: Fallback content if APIs fail

---

## 📁 Files Modified

1. `cloudflare-worker/src/daily-content-worker.ts` - Worker
2. `cloudflare-worker/wrangler-daily-content.jsonc` - Config
3. `lib/services/daily_content_service.dart` - Service
4. `lib/screens/ai/ai_chat_page.dart` - UI (uses Firestore)
5. `firebase/firestore.rules` - Security rules

---

## 🐛 Troubleshooting

**"Content not available yet"**
```bash
# Manually trigger worker
curl -X POST https://daily-content-worker.<account>.workers.dev
```

**"Permission denied"**
```bash
# Redeploy security rules
firebase deploy --only firestore:rules
```

**Check logs**
```bash
wrangler tail --config wrangler-daily-content.jsonc
```

---

See [DAILY_CONTENT_SYSTEM_COMPLETE.md](DAILY_CONTENT_SYSTEM_COMPLETE.md) for full documentation.
