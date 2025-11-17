# AI Test Generation with DeepSeek via Firebase Cloud Functions

This document explains the complete setup for secure AI-powered test generation using DeepSeek API through Firebase Cloud Functions.

## Architecture Overview

```
Flutter App (No API Keys)
    ↓
Firebase Cloud Function (Secure Proxy)
    ↓
DeepSeek API (API Key stored server-side)
```

## Benefits

✅ **Security**: API keys never exposed in client app
✅ **Cost Control**: Server-side rate limiting and monitoring
✅ **Scalability**: Firebase handles infrastructure
✅ **Reliability**: Automatic retries with exponential backoff
✅ **Audit Trail**: Server-side logging of all API calls

## Setup Steps

### 1. Get DeepSeek API Key

1. Visit https://platform.deepseek.com/api_keys
2. Sign up or log in
3. Create a new API key
4. Copy the key (starts with `sk-`)

### 2. Configure Firebase Cloud Function

#### Option A: Production Deployment

```bash
# Navigate to functions directory
cd functions

# Install dependencies
npm install

# Set the API key
firebase functions:config:set deepseek.api_key="your-sk-key-here"

# Deploy the function
firebase deploy --only functions:generateTestQuestions
```

#### Option B: Local Development (Emulator)

```bash
# Navigate to functions directory
cd functions

# Create .runtimeconfig.json file
echo '{
  "deepseek": {
    "api_key": "your-sk-key-here"
  }
}' > .runtimeconfig.json

# Start the emulator
firebase emulators:start --only functions
```

### 3. Update Flutter Configuration

In `lib/config/ai_config.dart`:

```dart
class AIConfig {
  // Set to true for production
  static const bool _isProduction = false; // Change to true when deploying
  
  // Your project ID
  static const String _productionProxyUrl =
      'https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net/generateTestQuestions';
}
```

### 4. Test the Setup

```bash
# Test the function
curl -X POST https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net/generateTestQuestions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-chat",
    "messages": [
      {"role": "system", "content": "You are a test writer."},
      {"role": "user", "content": "Create 2 science questions in JSON format"}
    ],
    "temperature": 0.7,
    "max_tokens": 1000
  }'
```

## File Structure

```
lib/
├── config/
│   └── ai_config.dart              # AI configuration
├── models/
│   └── test_question.dart          # TestQuestion model
├── services/
│   ├── ai_test_service.dart        # AI generation service
│   └── firestore_service.dart      # Firestore operations
├── exceptions/
│   └── ai_exceptions.dart          # Custom exceptions
├── screens/teacher/
│   └── create_ai_test_screen.dart  # UI for test generation
└── test/
    └── services/
        └── ai_test_service_test.dart # Unit tests

functions/
├── index.js                         # Cloud Function code
├── package.json                     # Dependencies
└── .runtimeconfig.json              # Local config (gitignored)
```

## Usage Example

### From Flutter App

```dart
import 'package:your_app/services/ai_test_service.dart';
import 'package:your_app/services/firestore_service.dart';

// Generate test
final aiService = AITestService();
final questions = await aiService.generateTest(
  className: 'Class 10',
  section: 'A',
  subject: 'Science',
  topic: 'Photosynthesis',
  totalMarks: 20,
  numQuestions: 10,
  difficulty: 'medium',
);

// Save to Firestore
final firestoreService = FirestoreService();
final docRef = await firestoreService.saveScheduledTest(
  className: 'Class 10',
  section: 'A',
  subject: 'Science',
  topic: 'Photosynthesis',
  totalMarks: 20,
  questions: questions,
  teacherId: 'teacher_id_here',
);

print('Test saved with ID: ${docRef.id}');
```

## Features

### 1. Automatic Marks Distribution

The service automatically distributes total marks across questions:

```dart
// If totalMarks = 20 and numQuestions = 6
// Result: [4, 4, 3, 3, 3, 3] marks per question
```

### 2. Duplicate Detection

Prevents duplicate questions using normalized text comparison:

```dart
// These are considered duplicates:
"What is H2O?" 
"what is h2o"
"What   is  H2O  ?"
```

### 3. Retry with Exponential Backoff

Automatically retries failed requests with increasing delays:

```
Attempt 1: Wait 1 second + random jitter
Attempt 2: Wait 2 seconds + random jitter
Attempt 3: Wait 4 seconds + random jitter
```

### 4. Context-Aware Generation

Avoids repeating previous questions:

```dart
final questions = await aiService.generateTest(
  // ... other params
  previousQuestions: await firestoreService.fetchPreviousQuestions(
    className: 'Class 10',
    section: 'A',
    subject: 'Science',
  ),
);
```

### 5. Error Handling

Comprehensive error handling with user-friendly messages:

- **Network errors**: "Please check your internet connection"
- **Rate limits**: "Too many requests. Wait 60 seconds"
- **Parse errors**: "The AI generated an invalid response"
- **Validation errors**: Lists specific validation failures

## Cloud Function Details

### Request Format

```json
{
  "model": "deepseek-chat",
  "messages": [
    {
      "role": "system",
      "content": "You are an expert educational test writer..."
    },
    {
      "role": "user",
      "content": "Create 10 questions for Class 10, Science..."
    }
  ],
  "temperature": 0.7,
  "max_tokens": 4000
}
```

### Response Format

```json
{
  "choices": [
    {
      "message": {
        "content": "[{\"type\": \"mcq\", \"questionText\": \"...\", ...}]"
      }
    }
  ]
}
```

### Error Responses

#### Rate Limit (429)

```json
{
  "error": "Rate limit exceeded",
  "message": "Too many requests. Please try again later.",
  "retryAfter": 60
}
```

#### Authentication Error (401)

```json
{
  "error": "Authentication failed",
  "message": "Invalid DeepSeek API key..."
}
```

## Testing

### Unit Tests

```bash
# Run unit tests
flutter test test/services/ai_test_service_test.dart
```

### Integration Tests

```bash
# Run integration tests
flutter test integration_test/ai_generation_integration_test.dart
```

### Manual Testing

Use the mock response feature:

```dart
final mockResponse = AITestService.getMockResponse();
final questions = aiService._parseResponse(mockResponse);
print('Generated ${questions.length} questions');
```

## Monitoring and Debugging

### View Cloud Function Logs

```bash
# Real-time logs
firebase functions:log --only generateTestQuestions

# Or in Firebase Console
# Go to Functions > generateTestQuestions > Logs
```

### Debug Flutter App

Check console output for detailed logging:

```
🤖 Calling AI proxy: https://...
📝 Request body: {...}
📡 Response status: 200
🧹 Cleaned response: [...]
✅ Parsed 10 questions
📊 Distributed 20 marks across 10 questions
✅ All questions are unique
✅ All questions are valid
💾 Saving test to Firestore...
✅ Test saved with ID: abc123
```

## Troubleshooting

### Problem: "Proxy URL not configured"

**Solution**: Set `_isProduction = true` in `ai_config.dart` after deploying the function

### Problem: "DeepSeek API key not configured"

**Solution**: Run `firebase functions:config:set deepseek.api_key="your-key"`

### Problem: Android Emulator can't reach localhost

**Solution**: The code automatically uses `10.0.2.2` for Android emulators

### Problem: "Rate limit exceeded"

**Solution**: Wait for the specified retry period or upgrade your DeepSeek plan

### Problem: "Invalid JSON response"

**Solution**: Check Cloud Function logs for the raw API response

## Cost Optimization

1. **Cache Previous Questions**: Reduce API calls by caching
2. **Batch Generation**: Generate multiple tests at once
3. **Rate Limiting**: Implement client-side rate limiting
4. **Usage Monitoring**: Track API usage in Firebase Console

## Security Best Practices

✅ **Never commit** `.runtimeconfig.json` to git
✅ **Use environment variables** for all secrets
✅ **Implement authentication** to restrict function access
✅ **Add rate limiting** to prevent abuse
✅ **Monitor usage** for unusual patterns
✅ **Rotate API keys** periodically

## Next Steps

1. ✅ Set up Firebase Cloud Function with DeepSeek API key
2. ✅ Update `ai_config.dart` with your project ID
3. ✅ Test with emulator locally
4. ✅ Deploy to production
5. ✅ Add teacher authentication checks
6. ✅ Implement usage analytics
7. ✅ Set up monitoring alerts

## Support

For issues or questions:
- Check Firebase Console logs
- Review DeepSeek API documentation
- Test with the ping function: `https://YOUR-PROJECT.cloudfunctions.net/ping`

## License

This implementation follows Firebase and DeepSeek terms of service.
