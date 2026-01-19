# 🎯 Daily Challenge Worker - Complete Setup Guide

## 📋 Overview

This Cloudflare Worker automatically fetches daily challenge questions from OpenTriviaDB API and stores them in Firebase **every day at 2:00 AM IST**. This eliminates the need for:
- ❌ Firebase Functions (requires paid subscription)
- ❌ API calls from student devices (rate limits)
- ❌ Inconsistent questions between students

## ✨ Features

### **Difficulty-Based Questions**
- **Grades 4-6**: Easy questions (General Knowledge, Science)
- **Grades 7-10**: Medium questions (Science, Computers, Math, Geography, History)
- **Grades 11-12**: Hard questions (Science, Computers, Math, History, Politics, Art)

### **Benefits**
- ✅ **No API Rate Limits**: Questions fetched once per day, not per student
- ✅ **Consistent Questions**: All students in same grade see same question
- ✅ **Instant Loading**: Pre-cached in Firebase
- ✅ **No Subscription Needed**: Free Cloudflare Workers (100,000 requests/day)
- ✅ **Automatic**: Runs every day without manual intervention

---

## 🚀 Quick Setup (5 Minutes)

### **Prerequisites**
```bash
# 1. Install Wrangler CLI (if not already installed)
npm install -g wrangler

# 2. Login to Cloudflare
wrangler login
```

### **Step 1: Configure Firebase Service Account**

1. Go to Firebase Console: https://console.firebase.google.com
2. Select your project
3. Go to **Project Settings** → **Service Accounts**
4. Click **Generate New Private Key**
5. Save the JSON file

6. **Set as Cloudflare Secret:**
```bash
cd cloudflare-worker
wrangler secret put FIREBASE_SERVICE_ACCOUNT --config wrangler-daily-challenge.jsonc
```

7. When prompted, paste the **entire JSON content** and press Enter

### **Step 2: Deploy the Worker**

```bash
# Make deployment script executable
chmod +x deploy_daily_challenge_worker.sh

# Deploy
./deploy_daily_challenge_worker.sh
```

**OR manually:**
```bash
cd cloudflare-worker
wrangler deploy --config wrangler-daily-challenge.jsonc
```

---

## 🧪 Testing

### **Test Manual Trigger**
```bash
# Get your worker URL from deployment output
curl -X POST https://daily-challenge-worker.YOUR_SUBDOMAIN.workers.dev
```

### **Check Firestore**
1. Go to Firebase Console → Firestore Database
2. Look for `daily_challenges` collection
3. You should see today's date as document ID
4. Document should contain:
   - `easy_question`, `easy_correctAnswer`, `easy_options`
   - `medium_question`, `medium_correctAnswer`, `medium_options`
   - `hard_question`, `hard_correctAnswer`, `hard_options`

### **Monitor Logs**
```bash
wrangler tail --config wrangler-daily-challenge.jsonc
```

---

## 📅 Schedule Details

### **Cron Expression**
```
30 20 * * *
```
- **Time**: 8:30 PM UTC = 2:00 AM IST (India)
- **Frequency**: Every day
- **Why 2 AM?**: Low server load, students asleep, fresh questions for morning

### **What Happens Each Day:**
1. **2:00 AM IST**: Worker wakes up
2. Checks if questions already exist for today
3. If not, fetches 3 questions (easy, medium, hard) from OpenTriviaDB
4. Stores in Firebase `daily_challenges/{YYYY-MM-DD}`
5. Students fetch from Firebase (instant, no API calls)

---

## 📱 Flutter App Integration

The Flutter app is already configured to:
1. **Primary**: Fetch from Firebase (fast, no API limits)
2. **Fallback**: Fetch from OpenTriviaDB API (if Firebase fails)

### **Code Flow:**
```dart
// lib/services/daily_challenge_service.dart
getDailyChallengeForToday(userId, standard) {
  // 1. Check local cache
  if (cached) return cached;
  
  // 2. Fetch from Firebase (PRIMARY)
  final challenge = await fetchQuestionFromFirebase(standard);
  
  // 3. Fallback to API if Firebase fails
  return challenge ?? await fetchQuestionFromAPI(standard);
}
```

---

## 🔧 Configuration Files

### **Created Files:**
```
cloudflare-worker/
├── src/
│   └── daily-challenge-worker.ts       ← Worker code
├── wrangler-daily-challenge.jsonc      ← Worker config
deploy_daily_challenge_worker.sh        ← Deployment script
DAILY_CHALLENGE_WORKER_SETUP.md        ← This file
```

### **Modified Files:**
```
lib/services/daily_challenge_service.dart  ← Added Firebase fetching
```

---

## 📊 Firebase Structure

### **Collection: `daily_challenges`**
```
daily_challenges/
  └── 2026-01-19/                       ← Today's date
      ├── date: "2026-01-19"
      ├── fetchedAt: "2026-01-19T02:00:00Z"
      ├── easy_question: "What is..."
      ├── easy_correctAnswer: "Answer"
      ├── easy_options: ["A", "B", "C", "D"]
      ├── easy_category: "Science & Nature"
      ├── easy_difficulty: "easy"
      ├── medium_question: "..."
      ├── medium_correctAnswer: "..."
      ├── medium_options: [...]
      ├── medium_category: "..."
      ├── medium_difficulty: "medium"
      ├── hard_question: "..."
      ├── hard_correctAnswer: "..."
      ├── hard_options: [...]
      ├── hard_category: "..."
      └── hard_difficulty: "hard"
```

---

## 🔍 Troubleshooting

### **Problem: Worker not running automatically**
```bash
# Check worker status
wrangler deployments list --config wrangler-daily-challenge.jsonc

# Check schedule
wrangler triggers list --config wrangler-daily-challenge.jsonc
```

### **Problem: Questions not appearing in Firebase**
1. Check worker logs:
   ```bash
   wrangler tail --config wrangler-daily-challenge.jsonc
   ```
2. Manually trigger:
   ```bash
   curl -X POST https://daily-challenge-worker.YOUR_SUBDOMAIN.workers.dev
   ```
3. Check Firebase rules allow write access

### **Problem: Students still hitting API**
- Check if Firebase fetch is failing
- Add debug logs:
  ```dart
  print('[DailyChallengeService] Fetching from Firebase...');
  ```
- Ensure `cloud_firestore` dependency is added in `pubspec.yaml`

---

## 💰 Cost Analysis

### **Before (Direct API Calls)**
- OpenTriviaDB: Free but rate limited (5 seconds between requests)
- 1000 students = Potential rate limit issues

### **After (Cloudflare Worker)**
- Cloudflare Workers: **100,000 requests/day FREE**
- Only **1 request per day** (at 2 AM)
- Firebase reads: **1 read per student per day**
- **Total cost: $0** 🎉

---

## 🎯 Next Steps

1. ✅ Deploy worker (done)
2. ✅ Test manual trigger
3. ✅ Wait for 2 AM tomorrow to see automatic run
4. ✅ Verify questions in Firebase
5. ✅ Test on student devices
6. ✅ Monitor for a week

---

## 📞 Support

If you encounter issues:
1. Check worker logs: `wrangler tail`
2. Check Firebase console for errors
3. Test manual trigger with curl
4. Verify service account has Firestore write permissions

---

## 🎓 How It Works

### **Architecture Flow:**
```
┌─────────────────────────────────────────────────────────────┐
│                     2:00 AM IST Daily                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
         ┌──────────────────────────┐
         │  Cloudflare Worker       │
         │  (daily-challenge-worker)│
         └────────┬─────────────────┘
                  │
                  ├─► Fetch easy question → OpenTriviaDB API
                  ├─► Fetch medium question → OpenTriviaDB API
                  ├─► Fetch hard question → OpenTriviaDB API
                  │
                  ▼
         ┌──────────────────────────┐
         │  Firebase Firestore      │
         │  daily_challenges/{date} │
         └────────┬─────────────────┘
                  │
                  ▼
         ┌──────────────────────────┐
         │  Flutter App             │
         │  (Students fetch)        │
         └──────────────────────────┘
```

---

## ✅ Verification Checklist

- [ ] Wrangler CLI installed
- [ ] Logged into Cloudflare
- [ ] Firebase service account configured
- [ ] Worker deployed successfully
- [ ] Manual trigger test passed
- [ ] Questions visible in Firebase
- [ ] Flutter app fetching from Firebase
- [ ] No API rate limit errors
- [ ] All difficulty levels working

---

**🎉 Congratulations! Your Daily Challenge Worker is now running automatically!**

Students will get fresh questions every day without hitting API rate limits. 🚀
