# 🚀 Firebase Proxy - Quick Setup Guide

## Required: Complete These Steps Now

### Step 1: Get DeepSeek API Key

1. Go to: **https://platform.deepseek.com/**
2. Sign up or log in
3. Navigate to **API Keys**
4. Click **Create API Key**
5. Copy the key (starts with `sk-`)

---

### Step 2: Configure Firebase Function

**Option A: Simple Way (Recommended for Testing)**

1. Navigate to functions folder:
   ```powershell
   cd d:\new_reward\functions
   ```

2. Create a `.env` file:
   ```powershell
   Copy-Item .env.example .env
   ```

3. Edit `.env` file and add your DeepSeek API key:
   ```
   DEEPSEEK_API_KEY=sk-YOUR-ACTUAL-KEY-HERE
   ```

**Option B: Production Way (For Deployed Apps)**

After your first deployment, set the secret in Firebase Console:
1. Go to: https://console.firebase.google.com/
2. Select your project: **lenv-cb08e** (LenV)
3. Go to: **Functions** → **Secrets**
4. Add secret: `DEEPSEEK_API_KEY` with your API key value

---

### Step 3: Deploy Firebase Function

```powershell
# Make sure you're in the project root
cd d:\new_reward

# Deploy the function
firebase deploy --only functions:generateTestQuestions
```

Wait for deployment to complete (usually 1-2 minutes).

**Note:** If you get a "permission denied" error, you need to:
1. **Enable required Google Cloud APIs first** - See `ENABLE_FIREBASE_APIS.md`
2. Run `firebase login` if not logged in
3. Make sure you have Owner/Editor role in the Firebase project

---

### Step 4: Enable Production Mode

1. Open: `lib/config/ai_config.dart`
2. Find line 21:
   ```dart
   static const bool _isProduction = false;
   ```
3. Change to:
   ```dart
   static const bool _isProduction = true;
   ```
4. Save the file

---

### Step 5: Test the App

```powershell
# Run Flutter app
flutter run
```

Then:
1. Log in as Teacher
2. Navigate to **AI Test Generator**
3. Fill in the form:
   - Subject: Mathematics
   - Topics: Algebra
   - Questions: 5
   - Select Class and Section
4. Click **Generate Test**
5. Wait 10-30 seconds
6. Questions should appear!

---

## ✅ Verification

### Check if Function is Deployed
```powershell
firebase functions:list
```

Should show: `generateTestQuestions`

### View Function Logs
```powershell
firebase functions:log
```

### Test Function Directly
Open browser and visit:
```
https://us-central1-lenv-cb08e.cloudfunctions.net/generateTestQuestions
```

Should see: "Method Not Allowed" (this is correct - function expects POST)

---

## 🐛 Common Issues

### Issue: "Firebase command not found"
**Solution:** Install Firebase CLI:
```powershell
npm install -g firebase-tools
firebase login
```

### Issue: "Permission denied"
**Solution:** Make sure you're logged into Firebase:
```powershell
firebase login
```

### Issue: "Deployment failed"
**Solution:** You need to enable Google Cloud APIs first:
```powershell
# Open the guide
notepad ENABLE_FIREBASE_APIS.md

# Or enable APIs directly at:
# https://console.cloud.google.com/apis/dashboard?project=lenv-cb08e
```

**Required APIs:**
1. Cloud Functions API
2. Cloud Build API  
3. Cloud Resource Manager API
4. Artifact Registry API
5. **Billing must be enabled** (has generous free tier)

### Issue: "API key not configured"
**Solution:** Make sure the .env file exists in functions folder:
```powershell
cd d:\new_reward\functions
dir .env
# If not found, create it:
Copy-Item .env.example .env
# Then edit .env and add your DeepSeek API key
```

### Issue: "Questions not generating"
**Solution:** 
1. Check Firebase logs: `firebase functions:log`
2. Verify API key is valid at https://platform.deepseek.com/
3. Check production mode is enabled in `ai_config.dart`

---

## 📊 Cost Estimate

### DeepSeek API
- **Free tier:** 100 requests/day
- **After free tier:** ~$0.001 per request
- **Example:** 1000 tests/month = ~$1/month

### Firebase Cloud Functions
- **Free tier:** 2 million calls/month
- **After free tier:** $0.40 per million calls
- **Example:** 10,000 tests/month = Free

**Total estimated cost:** ~$1-5/month for moderate usage

---

## 🎯 What Changed

### ❌ Before (Not Secure)
- API key stored in app code
- Anyone can decompile APK and steal key
- Can't change key without app update

### ✅ After (Secure)
- API key stored in Firebase (server-side only)
- No way to extract key from app
- Can change key anytime without app update

---

## 📝 Important Files

| File | Purpose |
|------|---------|
| `lib/config/ai_config.dart` | Proxy configuration |
| `lib/services/ai_test_service.dart` | AI service implementation |
| `functions/index_ai_proxy.js` | Firebase Cloud Function |
| `lib/screens/teacher/ai_test_generator_screen.dart` | UI screen |

---

## 🆘 Need Help?

1. **Check logs:**
   ```powershell
   firebase functions:log
   ```

2. **Check function status:**
   - Open Firebase Console
   - Go to Functions
   - Click `generateTestQuestions`
   - Check metrics and errors

3. **Test API key:**
   - Visit https://platform.deepseek.com/
   - Check API key is active
   - Check quota/usage

4. **Flutter debug:**
   ```powershell
   flutter run --verbose
   ```

---

## ✨ Summary

You successfully migrated from direct API to secure Firebase proxy! 🎉

**What you need to do:**
1. ✅ Get DeepSeek API key
2. ✅ Configure Firebase function with API key
3. ✅ Deploy Firebase function
4. ✅ Enable production mode
5. ✅ Test in app

**Time needed:** 5-10 minutes

**Status:** Ready to deploy! 🚀
