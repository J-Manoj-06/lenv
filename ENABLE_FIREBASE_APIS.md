# 🚨 IMPORTANT: Enable Firebase APIs First

## Your Firebase Project Details
- **Project ID:** `lenv-cb08e`
- **Project Name:** LenV
- **Account:** giridharannj@gmail.com

---

## ⚠️ Before Deploying - Enable Required APIs

You got a "permission denied" error because some Google Cloud APIs need to be enabled first.

### Step 1: Open Google Cloud Console

Click this link (it will open directly to your project):
```
https://console.cloud.google.com/apis/dashboard?project=lenv-cb08e
```

### Step 2: Enable Required APIs

Click on each link below to enable the APIs:

1. **Cloud Functions API** (Required)
   ```
   https://console.cloud.google.com/apis/library/cloudfunctions.googleapis.com?project=lenv-cb08e
   ```
   Click **"ENABLE"**

2. **Cloud Build API** (Required)
   ```
   https://console.cloud.google.com/apis/library/cloudbuild.googleapis.com?project=lenv-cb08e
   ```
   Click **"ENABLE"**

3. **Cloud Resource Manager API** (Required)
   ```
   https://console.cloud.google.com/apis/library/cloudresourcemanager.googleapis.com?project=lenv-cb08e
   ```
   Click **"ENABLE"**

4. **Artifact Registry API** (Required)
   ```
   https://console.cloud.google.com/apis/library/artifactregistry.googleapis.com?project=lenv-cb08e
   ```
   Click **"ENABLE"**

### Step 3: Enable Billing (Required for Cloud Functions)

Cloud Functions require a billing account (but has generous free tier):

1. Go to: https://console.cloud.google.com/billing?project=lenv-cb08e
2. Click **"Link a billing account"**
3. Create a new billing account or select existing one
4. **Don't worry:** Free tier includes:
   - 2 million function calls/month
   - 400,000 GB-seconds/month
   - 200,000 GHz-seconds/month

---

## After Enabling APIs - Deploy Again

```powershell
cd d:\new_reward
firebase deploy --only functions:generateTestQuestions
```

This should work now! ✅

---

## Alternative: Use Firebase Emulator (No Billing Required)

If you don't want to enable billing yet, you can test locally:

### 1. Create .env file
```powershell
cd d:\new_reward\functions
Copy-Item .env.example .env
notepad .env
```

Add your DeepSeek API key:
```
DEEPSEEK_API_KEY=sk-your-actual-key
```

### 2. Start Firebase Emulator
```powershell
cd d:\new_reward
firebase emulators:start --only functions
```

### 3. Update ai_config.dart
Keep `_isProduction = false` (it will use localhost)

### 4. Run Flutter App
```powershell
flutter run
```

The app will connect to your local emulator instead of deployed functions.

---

## 💰 Cost Information

### Free Tier (Monthly)
- ✅ Cloud Functions: 2 million invocations
- ✅ Cloud Build: 120 build-minutes/day
- ✅ Artifact Registry: 0.5 GB storage

### Estimated Costs
- **Light usage** (100 tests/day): $0/month
- **Moderate usage** (1000 tests/day): $1-2/month
- **Heavy usage** (5000 tests/day): $5-10/month

Most educational apps stay within free tier! 🎓

---

## Quick Decision Guide

### ✅ Enable Billing & Deploy (Recommended)
**Best for:**
- Production apps
- Apps used by multiple users
- Apps accessed from phones

**Steps:**
1. Enable all 4 APIs above
2. Link billing account
3. Deploy: `firebase deploy --only functions`

### 🏠 Use Local Emulator (Testing Only)
**Best for:**
- Development/testing
- Single developer
- No billing account yet

**Steps:**
1. Create `.env` file with API key
2. Run: `firebase emulators:start --only functions`
3. Keep `_isProduction = false`
4. Run: `flutter run`

---

## Need Help?

### Check Current APIs Status
Visit: https://console.cloud.google.com/apis/dashboard?project=lenv-cb08e

### Check Billing Status
Visit: https://console.cloud.google.com/billing?project=lenv-cb08e

### Firebase Support
Visit: https://firebase.google.com/support

---

**Choose your option and follow the steps above!** 🚀
