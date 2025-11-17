# ⚡ Direct DeepSeek API - Simple Setup (No Firebase Billing Required)

## ✅ What Changed

I've reverted from Firebase Cloud Functions proxy to **direct DeepSeek API calls** so you can test without enabling Firebase billing.

---

## 🚀 Quick Setup (2 Steps)

### Step 1: Get DeepSeek API Key

1. Visit: **https://platform.deepseek.com/**
2. Sign up or log in
3. Go to **API Keys** section
4. Click **Create API Key**
5. Copy your key (starts with `sk-`)

### Step 2: Add API Key to Your App

1. Open: `lib/config/ai_config.dart`
2. Find line 14:
   ```dart
   static const String apiKey = 'sk-your-deepseek-api-key-here';
   ```
3. Replace `'sk-your-deepseek-api-key-here'` with your actual API key:
   ```dart
   static const String apiKey = 'sk-abc123...your-real-key';
   ```
4. Save the file

### Step 3: Run Your App

```powershell
flutter run
```

That's it! The AI Test Generator should work now.

---

## 📊 How It Works

### Architecture

```
Flutter App → DeepSeek API (Direct)
     ↓
  API Key (in app code)
```

**Simple & Fast** ✅
- No Firebase setup needed
- No billing required
- Works immediately

⚠️ **Security Note:**
- API key is stored in app code
- OK for testing/development
- For production, use Firebase proxy (requires billing)

---

## 🧪 Test It

1. **Run the app:**
   ```powershell
   flutter run
   ```

2. **Log in as Teacher**

3. **Navigate to AI Test Generator**

4. **Fill in the form:**
   - Subject: Mathematics
   - Topics: Algebra, Equations
   - Questions: 5
   - Select Class and Section
   - Choose Difficulty

5. **Click "Generate Test"**

6. **Wait 10-30 seconds**

7. **Questions should appear!** ✨

---

## 🐛 Troubleshooting

### Error: "API key not configured"

**Solution:** Add your DeepSeek API key to `lib/config/ai_config.dart` line 14

### Error: "Failed to generate questions"

**Possible causes:**
1. **Invalid API key** - Check your key at https://platform.deepseek.com/
2. **No internet** - Check your connection
3. **API quota exceeded** - Check usage at DeepSeek dashboard

### Error: "Request timed out"

**Solution:** The AI is taking too long. Try:
- Reduce number of questions (try 3-5 instead of 10+)
- Check your internet speed
- Try again (sometimes API is slow)

### Questions are gibberish or malformed

**Solution:** This shouldn't happen with DeepSeek, but if it does:
- Try regenerating
- Reduce number of questions
- Check if your API key is valid

---

## 💰 Cost

### DeepSeek API Pricing
- **Free tier:** Limited requests per day
- **Pay-as-you-go:** Very cheap (~$0.001 per request)
- **Typical usage:** 
  - 10 tests/day = ~$0.01/day = ~$0.30/month
  - 100 tests/day = ~$0.10/day = ~$3/month

**Much cheaper than Firebase billing!** 💵

---

## 📝 Files Modified

| File | Status |
|------|--------|
| `lib/config/ai_config.dart` | ✅ Updated for direct API |
| `lib/services/ai_test_service.dart` | ✅ Updated to call DeepSeek directly |
| `lib/screens/teacher/ai_test_generator_screen.dart` | ✅ Already compatible |

**Everything else unchanged** - Firebase files are still there but not used.

---

## 🔄 Want Firebase Proxy Later?

When you're ready to enable billing and use the secure Firebase proxy:

1. Enable Firebase billing
2. Deploy Cloud Function (see `ENABLE_FIREBASE_APIS.md`)
3. Update `ai_config.dart` back to proxy mode

For now, direct API is perfect for testing! 👍

---

## ✅ Summary

**What you need to do:**
1. ✅ Get DeepSeek API key from https://platform.deepseek.com/
2. ✅ Add key to `lib/config/ai_config.dart` line 14
3. ✅ Run: `flutter run`
4. ✅ Test AI Test Generator

**Time needed:** 2-3 minutes

**Cost:** ~$0.01 per test (free tier available)

**Status:** ✅ Ready to use immediately!

---

**🎉 You can now test AI features without Firebase billing!**
