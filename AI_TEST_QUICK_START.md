# Quick Start Guide - AI Test Generation

## 🚀 Get Started in 5 Minutes

### Step 1: Set Up Proxy Server (2 minutes)

Create a file `proxy-server.js`:

```javascript
const express = require('express');
const app = express();
app.use(express.json());

// MOCK RESPONSE - No API key needed for testing!
app.post('/generate', async (req, res) => {
  console.log('Received request:', req.body);
  
  // Simulate processing delay
  setTimeout(() => {
    const mockResponse = {
      choices: [{
        message: {
          content: JSON.stringify([
            {
              type: 'mcq',
              questionText: 'What is 2 + 2?',
              marks: 2,
              options: ['3', '4', '5', '6'],
              correctAnswer: 'B'
            },
            {
              type: 'truefalse',
              questionText: 'The Earth is flat.',
              marks: 1,
              correctAnswer: 'false'
            },
            {
              type: 'mcq',
              questionText: 'Which planet is closest to the Sun?',
              marks: 2,
              options: ['Venus', 'Mercury', 'Earth', 'Mars'],
              correctAnswer: 'B'
            }
          ])
        }
      }]
    };
    
    res.json(mockResponse);
  }, 2000); // 2 second delay to simulate real API
});

app.listen(3000, () => {
  console.log('✅ Mock proxy server running on http://localhost:3000');
  console.log('📱 Android emulator: http://10.0.2.2:3000');
});
```

Install and run:
```bash
npm install express
node proxy-server.js
```

### Step 2: Add Navigation Button (1 minute)

Find your teacher dashboard screen (e.g., `teacher_home_screen.dart`) and add:

```dart
import '../screens/teacher/create_ai_test_screen.dart';

// Inside your build method, add this button:
ElevatedButton.icon(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CreateAITestScreen(),
      ),
    );
  },
  icon: const Icon(Icons.auto_awesome),
  label: const Text('AI Test Generator'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.purple,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  ),
),
```

### Step 3: Run the App (1 minute)

```bash
# Terminal 1: Keep proxy server running
node proxy-server.js

# Terminal 2: Run Flutter app
flutter run
```

### Step 4: Test the Feature (1 minute)

1. Open app and login as teacher
2. Click "AI Test Generator" button
3. Fill in the form:
   - Class: Grade 10
   - Section: A
   - Subject: Mathematics
   - Topic: Basic Arithmetic
   - Questions: 3
   - Total Marks: 5
4. Click "Generate Test with AI"
5. Wait 2-3 seconds
6. Review generated questions
7. Click "Save Test"

**Done!** ✅

---

## 🔥 Alternative: Test Without Proxy

If you don't want to set up a proxy server, you can use the built-in mock:

### Edit `ai_test_service.dart`:

Find the `_callProxyWithRetry` method and replace it with:

```dart
Future<String> _callProxyWithRetry(String prompt) async {
  // MOCK MODE - for testing without proxy
  await Future.delayed(const Duration(seconds: 2));
  return AITestService.getMockResponse();
}
```

This will return fake questions without calling any server!

---

## 🎯 Expected Behavior

### Success Flow
1. Form validation passes ✅
2. Loading dialog appears with spinner
3. Message: "Generating test questions..."
4. Wait 2-3 seconds
5. Preview screen appears with 3 questions
6. Questions are editable (marks, delete)
7. Click "Save Test"
8. Success message: "Test saved successfully!"
9. Navigate back to dashboard

### Error Scenarios

#### Network Error
- **Cause**: Proxy server not running
- **Message**: "Network Error - No internet connection. Check network and retry."
- **Action**: Retry button available

#### Timeout
- **Cause**: Proxy takes >30 seconds
- **Message**: "Request Timeout - Request timed out after 30 seconds."
- **Action**: Retry button available

#### Validation Error
- **Cause**: Empty fields or invalid marks
- **Message**: Field-specific error messages
- **Action**: Fix errors and retry

---

## 📱 Platform-Specific URLs

The app automatically detects your platform:

| Platform | Proxy URL |
|----------|-----------|
| Android Emulator | `http://10.0.2.2:3000` |
| iOS Simulator | `http://localhost:3000` |
| Physical Device | `https://your-server.com` |
| Production | `https://your-server.com` |

---

## 🐛 Troubleshooting

### "Network Error" immediately
```bash
# Check if proxy is running
curl http://localhost:3000/generate -d '{"test":"data"}' -H "Content-Type: application/json"

# Should return mock response
```

### App can't reach proxy
```bash
# For Android Emulator
adb reverse tcp:3000 tcp:3000

# OR use 10.0.2.2 (already configured)
```

### Want to see what's being sent?
Add logging to proxy server:
```javascript
app.post('/generate', async (req, res) => {
  console.log('📥 Received:', JSON.stringify(req.body, null, 2));
  // ... rest of code
});
```

---

## 🎉 Quick Verification Checklist

- [ ] Proxy server running on port 3000
- [ ] Flutter app running
- [ ] Navigation button visible in teacher dashboard
- [ ] Form accepts input
- [ ] Generate button triggers loading
- [ ] Questions appear in preview
- [ ] Edit marks works
- [ ] Delete question works
- [ ] Save test succeeds
- [ ] Test appears in Firebase

---

## 💡 Pro Tips

1. **Fast Testing**: Use mock mode (no proxy needed)
2. **Debug Mode**: Check console logs in proxy server
3. **Network Issues**: Use `adb reverse` for Android
4. **Firebase**: Check `scheduledTests` collection
5. **Regenerate**: Click "Regenerate" for different questions

---

## 📞 Need Help?

Check the full documentation: `AI_TEST_GENERATION_SUMMARY.md`

Common files to check:
- `lib/config/ai_config.dart` - Proxy URL configuration
- `lib/services/ai_test_service.dart` - Core logic
- `lib/screens/teacher/create_ai_test_screen.dart` - UI

---

**Quick Start Version**: 1.0  
**Time to Complete**: ~5 minutes  
**Difficulty**: Easy 🟢
