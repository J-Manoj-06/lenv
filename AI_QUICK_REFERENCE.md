# 🚀 AI Test Generation - Quick Reference Card

## ⚡ 5-Minute Setup

### 1. Get API Key
```
https://platform.deepseek.com/api_keys
→ Create key (starts with sk-)
```

### 2. Configure Firebase
```bash
firebase functions:config:set deepseek.api_key="your-key"
firebase deploy --only functions:generateTestQuestions
```

### 3. Update Flutter Config
```dart
// lib/config/ai_config.dart
static const bool _isProduction = true;
```

### 4. Test
```bash
flutter run
# Navigate to AI Test Generator → Generate Test
```

## 📝 Basic Usage

```dart
// Generate
final aiService = AITestService();
final questions = await aiService.generateTest(
  className: 'Class 10',
  section: 'A',
  subject: 'Science',
  topic: 'Photosynthesis',
  totalMarks: 20,
  numQuestions: 10,
);

// Save
final firestoreService = FirestoreService();
await firestoreService.saveScheduledTest(
  className: 'Class 10',
  section: 'A',
  subject: 'Science',
  topic: 'Photosynthesis',
  totalMarks: 20,
  questions: questions,
  teacherId: 'teacher_id',
);
```

## 🔥 Common Commands

```bash
# Deploy function
firebase deploy --only functions:generateTestQuestions

# View logs
firebase functions:log --tail

# Test function
curl -X POST https://YOUR-PROJECT.cloudfunctions.net/generateTestQuestions \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-chat","messages":[...]}'

# Run Flutter
flutter run

# Hot restart
r (in terminal where flutter run is active)
```

## 🐛 Quick Fixes

| Problem | Solution |
|---------|----------|
| "Proxy URL not configured" | Set `_isProduction = true` |
| "API key not configured" | Run `firebase functions:config:set deepseek.api_key="..."` |
| "Network error" | Check URL in `ai_config.dart` |
| "Invalid JSON" | Check Firebase logs, retry request |
| Android can't connect | Code auto-uses 10.0.2.2, check firewall |

## 📊 What Happens

```
1. Flutter calls Cloud Function
2. Function adds API key, calls DeepSeek
3. DeepSeek generates questions in JSON
4. Function returns to Flutter
5. Flutter parses, validates questions
6. Distributes marks automatically
7. Checks for duplicates
8. Saves to Firestore scheduledTests
```

## 🎯 Key Files

| File | Purpose |
|------|---------|
| `lib/config/ai_config.dart` | Configuration |
| `lib/services/ai_test_service.dart` | Generation logic |
| `lib/services/firestore_service.dart` | Save to Firestore |
| `lib/models/test_question.dart` | Question model |
| `lib/exceptions/ai_exceptions.dart` | Error types |
| `functions/index.js` | Cloud Function |

## 🧪 Test Commands

```bash
# Unit tests
flutter test test/services/ai_test_service_test.dart

# Test function health
curl https://YOUR-PROJECT.cloudfunctions.net/ping

# View Firebase console
https://console.firebase.google.com/
```

## 📱 In-App Testing

1. Hot restart app
2. Navigate to AI Test Generator
3. Fill form:
   - Class: Class 10
   - Section: A
   - Subject: Science
   - Topic: Photosynthesis
   - Marks: 20
   - Questions: 10
4. Click "Generate Test"
5. Check console logs
6. Verify questions displayed
7. Save to Firestore
8. Check Firebase Console

## 🔐 Security

✅ API key on server ONLY
✅ Never in client code
✅ HTTPS everywhere
✅ Server-side validation
✅ Rate limit protection

## 💰 Cost Tips

- Use appropriate token limits
- Cache previous questions
- Implement client-side throttling
- Monitor usage in Firebase Console

## 📚 Documentation

- `AI_TEST_QUICK_START.md` - Quick start guide
- `AI_TEST_GENERATION_SETUP.md` - Complete setup
- `AI_IMPLEMENTATION_SUMMARY.md` - Full summary

## 🆘 Help

1. Check Firebase Functions logs
2. Test endpoint with curl
3. Verify API key set
4. Check `_isProduction` flag
5. Review console output

## ✅ Production Checklist

- [ ] DeepSeek API key obtained
- [ ] Firebase function configured
- [ ] `_isProduction = true`
- [ ] Function deployed
- [ ] Tested with curl
- [ ] Tested in Flutter app
- [ ] Authentication added
- [ ] Monitoring enabled

---

**Ready to Go!** 🎉

Need help? Check the full documentation:
- AI_TEST_QUICK_START.md
- AI_TEST_GENERATION_SETUP.md
- AI_IMPLEMENTATION_SUMMARY.md
