# DeepSeek Cloud Function Integration

This guide explains how to deploy and use the Firebase Cloud Function `generateQuestions` that securely calls the DeepSeek Chat Completion API. The DeepSeek API key never resides in Flutter.

---
## 1. Prerequisites
- Firebase project initialized (web + android + ios already configured)
- Firebase CLI installed: https://firebase.google.com/docs/cli
- Logged in: `firebase login`
- Project selected: `firebase use <your-project-id>`

---
## 2. Set DeepSeek API Key (Secure Runtime Config)
Replace `YOUR_KEY_HERE` with your actual DeepSeek API key.
```powershell
firebase functions:config:set deepseek.key="YOUR_KEY_HERE"
firebase functions:config:get
```
Verify output includes:
```json
{
  "deepseek": {
    "key": "YOUR_KEY_HERE"
  }
}
```

To deploy config only:
```powershell
firebase deploy --only functions:generateQuestions
```

If you ever rotate the key, re-run the `functions:config:set` command and deploy again.

---
## 3. Function Source Overview
**File:** `functions/index.js`
- Callable name: `generateQuestions`
- Inputs:
  - `topic`: String (non-empty)
  - `count`: Integer 3–100
- Output: A **JSON string** containing three arrays: `mcq`, `true_false`, `match_the_following`

### Quick Anatomy
```js
exports.generateQuestions = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 60, memory: '256MB' })
  .https.onCall(async (data, context) => { /* ... */ });
```

---
## 4. Deploy the Function
From project root:
```powershell
cd functions
npm install
cd ..
firebase deploy --only functions:generateQuestions
```

To emulate locally (optional):
```powershell
firebase emulators:start --only functions
```
Then point Flutter to the emulator before calling:
```dart
FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001);
```

---
## 5. Flutter Dependency
Added to `pubspec.yaml`:
```yaml
dependencies:
  cloud_functions: ^5.0.0
```
Run:
```powershell
flutter pub get
```

---
## 6. Flutter Service Usage
**File:** `lib/services/question_service.dart`
```dart
final service = QuestionService();
final map = await service.generateQuestions(topic: 'Algebra', count: 9);
print(map['mcq']);
```
Structure of returned map:
```json
{
  "mcq": [ { "question": "...", "options": ["A","B","C","D"], "answer": 1 } ],
  "true_false": [ { "question": "...", "answer": true } ],
  "match_the_following": [ { "question": "...", "left": ["..."], "right": ["..."], "answer": {"Item1":"Match2"} } ]
}
```

---
## 7. Demo Widget
**File:** `lib/widgets/generate_questions_demo.dart` provides a ready-to-use UI card to test the function.
Add it anywhere in your teacher dashboard:
```dart
const GenerateQuestionsDemo(),
```

---
## 8. Error Handling Codes
| Code | Cause | Flutter Exception |
|------|-------|-------------------|
| invalid-argument | Bad input (missing topic / invalid count) | FirebaseFunctionsException |
| failed-precondition | Missing API key configuration | FirebaseFunctionsException |
| resource-exhausted | DeepSeek rate limit hit | FirebaseFunctionsException |
| permission-denied | Bad API key / unauthorized | FirebaseFunctionsException |
| unavailable | Network / API unreachable | FirebaseFunctionsException |
| data-loss | Model returned malformed JSON | FirebaseFunctionsException |
| internal | Unexpected server error | FirebaseFunctionsException |

**Flutter handling example:**
```dart
try {
  final data = await QuestionService().generateQuestions(topic: 'Physics', count: 12);
} on FirebaseFunctionsException catch (e) {
  // show e.code & e.message
} catch (e) {
  // generic error
}
```

---
## 9. Rotating the API Key
```powershell
firebase functions:config:set deepseek.key="NEW_KEY"
firebase deploy --only functions:generateQuestions
```
No Flutter changes needed.

---
## 10. Production Recommendations
- Restrict callable function to authenticated users (check `context.auth` inside the function)
- Add quota / rate limiting in app logic (e.g., one generation per 30 seconds)
- Log usage metrics (could integrate with Firestore or Analytics)
- Monitor logs: `firebase functions:log --only generateQuestions`
- Add retries in Flutter if you frequently hit transient errors

---
## 11. Testing the Function Directly (Optional)
Using curl with emulator (after starting emulators):
```powershell
curl -X POST localhost:5001/YOUR_PROJECT_ID/us-central1/generateQuestions \
  -H "Content-Type: application/json" \
  -d '{"data":{"topic":"Chemistry","count":9}}'
```

---
## 12. Common Issues
| Issue | Fix |
|-------|-----|
| HttpsError failed-precondition | Ensure config set via functions:config:set |
| data-loss (invalid JSON) | Retry; model occasionally adds stray text |
| resource-exhausted | Implement client-side cooldown & retry |
| permission-denied | Verify API key and DeepSeek account status |

---
## 13. Migration From OpenRouter
If you previously used OpenRouter client-side:
1. Remove API key from any Flutter files
2. Use this Cloud Function instead
3. Confirm no references to old service remain

---
## 14. Quick Verification Checklist
- [ ] `functions/index.js` exists
- [ ] `functions/package.json` installed
- [ ] DeepSeek key set in functions config
- [ ] `generateQuestions` deployed
- [ ] Flutter dependency `cloud_functions` installed
- [ ] Service call returns valid JSON
- [ ] Demo widget renders

---
## 15. Next Enhancements (Optional)
- Add streaming support if DeepSeek offers it
- Cache generated questions per topic to reduce cost
- Add language parameter for multilingual generation
- Add difficulty tiers (easy / medium / hard) in prompt
- Persist generation requests & responses for audit

---
**Done. Your secure DeepSeek integration via Firebase Cloud Functions is ready.**
