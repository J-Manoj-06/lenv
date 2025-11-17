# 🧪 AI Test Generation - Testing Mode Setup

## Quick Testing Without Firebase Setup

This guide shows you how to test the AI test generation feature using your DeepSeek API key directly, **without setting up Firebase Cloud Functions**.

## ⚡ Quick Setup (3 Steps)

### Step 1: Get Your DeepSeek API Key

1. Visit: https://platform.deepseek.com/api_keys
2. Sign up or log in
3. Create a new API key
4. Copy the key (starts with `sk-`)

### Step 2: Paste Your API Key

Open `lib/config/ai_test_config.dart` and:

1. **Line 15**: Replace `'PASTE_YOUR_API_KEY_HERE'` with your actual API key
2. **Line 18**: Change `useDirectAPI = false` to `useDirectAPI = true`

```dart
// Before:
static const String directApiKey = 'PASTE_YOUR_API_KEY_HERE';
static const bool useDirectAPI = false;

// After:
static const String directApiKey = 'sk-your-actual-key-here';
static const bool useDirectAPI = true;  // ✅ Changed to true
```

### Step 3: Run and Test

```bash
flutter run
```

Then:
1. Navigate to **AI Test Generator** screen
2. Fill in the form:
   - Subject: `Science`
   - Topics: `Photosynthesis`
   - Question Count: `5`
   - Select Class and Section
3. Click **"Generate"**
4. Watch the magic! 🎉

## 📊 What You'll See

When testing mode is enabled, you'll see this in the console:

```
═══════════════════════════════════════════════════════
🤖 AI Test Configuration Status
═══════════════════════════════════════════════════════
Mode: Direct API (Testing)
Status: ✅ Direct API mode enabled (Testing)
Endpoint: https://api.deepseek.com/v1/chat/completions
Model: deepseek-chat
Temperature: 0.7
Max Tokens: 4000
═══════════════════════════════════════════════════════
🤖 Calling AI: https://api.deepseek.com/v1/chat/completions
📝 Mode: Direct API (Testing)
📝 Using model: deepseek-chat
✅ AI responded successfully
📄 Response length: 2543 characters
✨ Generated 5 questions successfully!
```

## 🔄 Switch Between Modes

### Testing Mode (Direct API)
**Use for**: Quick testing, development, debugging

```dart
// lib/config/ai_test_config.dart
static const String directApiKey = 'sk-your-key-here';
static const bool useDirectAPI = true;  // ✅ Testing mode
```

**Pros**: 
- ✅ Fast setup (no Firebase needed)
- ✅ Easy debugging
- ✅ Direct API access

**Cons**:
- ⚠️ API key in app code (not secure for production)
- ⚠️ No rate limiting protection
- ⚠️ No server-side monitoring

### Production Mode (Firebase Function)
**Use for**: Production deployment, published apps

```dart
// lib/config/ai_test_config.dart
static const bool useDirectAPI = false;  // ✅ Production mode
```

**Pros**:
- ✅ API key stored securely on server
- ✅ Rate limiting and monitoring
- ✅ Better security
- ✅ Audit logging

**Cons**:
- ⚠️ Requires Firebase setup
- ⚠️ More complex configuration

## 🔐 Security Notes

### ⚠️ IMPORTANT: Testing Mode Security

When `useDirectAPI = true`:
- Your API key is **hardcoded in the app**
- Anyone who decompiles your app can see it
- **ONLY use for testing on your local machine**
- **NEVER deploy to production with testing mode enabled**
- **NEVER commit the file with your real API key to Git**

### ✅ For Production

Always use Firebase Cloud Functions:
```dart
static const bool useDirectAPI = false;  // Production mode
```

## 🧪 Testing Checklist

- [ ] Got DeepSeek API key from https://platform.deepseek.com/
- [ ] Pasted key in `lib/config/ai_test_config.dart` line 15
- [ ] Set `useDirectAPI = true` in line 18
- [ ] Ran `flutter run`
- [ ] Navigated to AI Test Generator
- [ ] Successfully generated test questions
- [ ] Verified questions display correctly

## 📝 Example Test Data

Try these test parameters:

### Test 1: Science
- **Subject**: Science
- **Topics**: Photosynthesis, Plant Biology
- **Difficulty**: Medium
- **Question Count**: 5
- **Class**: Class 10
- **Section**: A

### Test 2: Mathematics
- **Subject**: Mathematics
- **Topics**: Algebra, Quadratic Equations
- **Difficulty**: Hard
- **Question Count**: 10
- **Class**: Class 9
- **Section**: B

### Test 3: English
- **Subject**: English
- **Topics**: Grammar, Tenses
- **Difficulty**: Easy
- **Question Count**: 8
- **Class**: Class 8
- **Section**: A

## 🐛 Troubleshooting

### Error: "Direct API key not configured"

**Solution**: Check `lib/config/ai_test_config.dart`:
```dart
// Make sure you replaced the placeholder
static const String directApiKey = 'sk-your-actual-key-here';  // ✅ Real key
static const bool useDirectAPI = true;  // ✅ Must be true
```

### Error: "Invalid API key" or 401

**Solution**: 
1. Verify your API key is correct
2. Check it starts with `sk-`
3. Try generating a new key at https://platform.deepseek.com/

### Error: "Network error"

**Solution**:
1. Check your internet connection
2. Try accessing https://api.deepseek.com/ in browser
3. Check if your firewall is blocking the request

### Error: "Rate limit exceeded"

**Solution**:
1. Wait 60 seconds and try again
2. Check your DeepSeek plan limits
3. Consider upgrading your plan

### Questions look weird or incomplete

**Solution**:
1. Try regenerating (sometimes AI gives inconsistent results)
2. Reduce question count (try 5 instead of 20)
3. Be more specific in your topic description

## 📊 Configuration File Locations

```
lib/
├── config/
│   ├── ai_config.dart           # OLD: Direct API only (can ignore)
│   └── ai_test_config.dart      # NEW: Testing + Production modes ✅
│
└── services/
    └── ai_test_service.dart     # Updated to use ai_test_config.dart
```

## 🎯 Next Steps

### After Testing Successfully

1. **Switch to Production Mode**:
   ```dart
   static const bool useDirectAPI = false;
   ```

2. **Set up Firebase Cloud Function**:
   - Follow: `AI_TEST_QUICK_START.md`
   - Or: `AI_TEST_GENERATION_SETUP.md`

3. **Deploy Your App**:
   - With Firebase function, your API key is secure
   - Ready for production use

## 💡 Pro Tips

1. **Start Small**: Test with 3-5 questions first
2. **Check Console**: Watch for the configuration status output
3. **Save Key Safely**: Store your API key in a password manager
4. **Don't Commit**: Add `ai_test_config.dart` to `.gitignore` if you paste real keys
5. **Use Production Mode**: Before deploying your app

## 📚 Related Documentation

- **AI_TEST_QUICK_START.md**: Quick start for Firebase setup
- **AI_TEST_GENERATION_SETUP.md**: Complete Firebase setup guide
- **AI_IMPLEMENTATION_SUMMARY.md**: Full feature documentation
- **AI_QUICK_REFERENCE.md**: Quick command reference

## ✅ Summary

**Testing Mode** (Direct API):
```
You → DeepSeek API (direct)
```

**Production Mode** (Firebase):
```
You → Firebase Function → DeepSeek API
```

Both work with the same code! Just flip the `useDirectAPI` switch.

---

**Happy Testing!** 🎉

Need help? Check the console output for detailed configuration status.
