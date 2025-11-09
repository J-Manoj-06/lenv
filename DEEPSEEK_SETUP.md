# 🤖 DeepSeek AI Integration Guide

This guide will help you set up and use DeepSeek AI in your Flutter app for AI-powered test question generation.

---

## 📋 Table of Contents

1. [Getting Your API Key](#getting-your-api-key)
2. [Configuration](#configuration)
3. [Testing the Integration](#testing-the-integration)
4. [Features](#features)
5. [Troubleshooting](#troubleshooting)
6. [API Information](#api-information)

---

## 🔑 Getting Your API Key

### Step 1: Visit DeepSeek Platform

1. Open your browser and go to: **https://platform.deepseek.com/**
2. Sign up for a new account or log in if you already have one

### Step 2: Create API Key

1. After logging in, navigate to the **API Keys** section
2. Click **"Create New API Key"** or similar button
3. Give your API key a name (e.g., "Flutter Test Generator")
4. Copy the generated API key (it will look like: `sk-xxxxxxxxxxxxxxxxxxxxx`)

⚠️ **IMPORTANT**: Save this key securely! You won't be able to see it again after closing the page.

---

## ⚙️ Configuration

### Step 1: Open Configuration File

Navigate to and open this file in your project:
```
lib/core/config/deepseek_config.dart
```

### Step 2: Paste Your API Key

Find this line:
```dart
static const String apiKey = "PASTE_YOUR_DEEPSEEK_API_KEY_HERE";
```

Replace `PASTE_YOUR_DEEPSEEK_API_KEY_HERE` with your actual API key:
```dart
static const String apiKey = "sk-your-actual-api-key-here";
```

### Step 3: Install Dependencies

Run this command in your terminal:
```bash
flutter pub get
```

This will install the `http` package needed for API calls.

---

## ✅ Testing the Integration

### Step 1: Run Your App

```bash
flutter run
```

### Step 2: Navigate to AI Test Generator

1. Log in as a Teacher
2. Go to the **AI Test Generator** screen
3. Fill in the form:
   - **Subject**: Mathematics
   - **Topics**: Algebra, Linear Equations
   - **Number of Questions**: 5
   - **Difficulty**: Medium
   - **Class**: Select any class

### Step 3: Generate Questions

1. Click the **"Generate"** button
2. Wait a few seconds for the AI to generate questions
3. You should see AI-generated multiple-choice questions appear!

### Success Indicators

✅ Questions appear after clicking Generate
✅ Each question has 4 options (A, B, C, D)
✅ Questions are relevant to your subject and topics
✅ You see a green success message

### Error Indicators

❌ **"DeepSeek API not configured"** → You haven't pasted your API key yet
❌ **"Failed to generate questions"** → Check your API key and internet connection
❌ **"Invalid JSON"** → The AI returned an unexpected format (rare, try again)

---

## 🎯 Features

### 1. AI Test Question Generation

The DeepSeek service can generate:
- **Multiple-choice questions** with 4 options
- **Questions tailored to specific subjects and topics**
- **Difficulty-appropriate questions** (Easy, Medium, Hard)
- **Grade-level appropriate content**
- **Explanations for correct answers**

### 2. Customizable Parameters

You can adjust these settings in `deepseek_config.dart`:

```dart
// Model selection
static const String defaultModel = "deepseek-chat";  // General purpose
static const String coderModel = "deepseek-coder";   // For programming topics
static const String reasonerModel = "deepseek-reasoner"; // For complex reasoning

// Generation parameters
static const double defaultTemperature = 0.7;  // Creativity level (0.0-1.0)
static const int defaultMaxTokens = 2000;     // Response length
static const double defaultTopP = 0.9;        // Nucleus sampling
```

### 3. Additional AI Features

The `DeepSeekService` also supports:

#### Student Feedback Generation
```dart
final feedback = await DeepSeekService().generateFeedback(
  studentWork: "2x + 5",
  question: "Solve for x: 3x + 5 = 14",
  correctAnswer: "x = 3",
);
```

#### Study Tips Generation
```dart
final tips = await DeepSeekService().generateStudyTips(
  subject: "Mathematics",
  topic: "Quadratic Equations",
  grade: "10",
);
```

---

## 🔧 Troubleshooting

### Problem: "DeepSeek API not configured"

**Solution:**
1. Make sure you've replaced `PASTE_YOUR_DEEPSEEK_API_KEY_HERE` with your actual API key
2. Run `flutter pub get` to refresh
3. Hot restart your app (press 'R' in terminal or restart from IDE)

### Problem: "Failed to generate questions"

**Possible causes:**
1. **Invalid API Key** → Double-check you copied the full key
2. **No internet connection** → Check your network
3. **API quota exceeded** → Check your DeepSeek account usage limits
4. **API service down** → Check https://status.deepseek.com/

### Problem: Questions are not relevant

**Solution:**
1. Be more specific in the "Topics" field
   - ❌ Bad: "Math"
   - ✅ Good: "Linear equations, slope-intercept form, graphing lines"

2. Adjust the temperature in `deepseek_config.dart`:
   - Lower (0.3-0.5) = more focused, predictable
   - Higher (0.7-0.9) = more creative, varied

### Problem: App crashes when generating

**Solution:**
1. Check the Debug Console for error messages
2. Ensure `http` package is installed: `flutter pub get`
3. Verify your API key doesn't have extra spaces

### Problem: JSON parsing errors

**Solution:**
1. This is rare but can happen if the AI returns unexpected format
2. Try generating again with different parameters
3. Check `DeepSeekConfig.enableLogging = true` to see raw responses

---

## 📊 API Information

### Official Documentation
- **Website**: https://platform.deepseek.com/
- **API Docs**: https://platform.deepseek.com/api-docs
- **Pricing**: https://platform.deepseek.com/pricing
- **Status Page**: https://status.deepseek.com/

### Model Information

| Model | Best For | Speed | Quality |
|-------|----------|-------|---------|
| `deepseek-chat` | General questions, explanations | Fast | High |
| `deepseek-coder` | Programming, technical topics | Fast | Very High |
| `deepseek-reasoner` | Complex reasoning, math | Medium | Excellent |

### Rate Limits

- Check your plan on the DeepSeek platform
- Free tier typically includes a limited number of requests per month
- Upgrade if you need higher limits

### Cost

- DeepSeek is generally more affordable than GPT-4
- Pricing is based on tokens used (input + output)
- Check current pricing at: https://platform.deepseek.com/pricing

---

## 🔒 Security Best Practices

### ⚠️ Important Security Notes

1. **Never commit API keys to public repositories**
   - Add `lib/core/config/deepseek_config.dart` to `.gitignore` if sharing code

2. **For production apps:**
   - Store API keys on your backend server
   - Make API calls from your server, not the Flutter app
   - This prevents users from extracting your API key

3. **Monitor usage:**
   - Regularly check your DeepSeek dashboard for usage
   - Set up usage alerts to prevent unexpected charges

---

## 🎓 Example Usage

### Basic Test Generation

```dart
final deepSeekService = DeepSeekService();

try {
  final questions = await deepSeekService.generateTestQuestions(
    subject: "Science",
    topics: "Photosynthesis, Plant Biology",
    questionCount: 10,
    difficulty: "Medium",
    grade: "8",
  );
  
  print("Generated ${questions.length} questions!");
} catch (e) {
  print("Error: $e");
}
```

### Custom Parameters

```dart
// In deepseek_config.dart, you can customize:

// Use the coder model for programming questions
static const String defaultModel = "deepseek-coder";

// Make responses more creative
static const double defaultTemperature = 0.9;

// Allow longer responses
static const int defaultMaxTokens = 3000;
```

---

## 📞 Support

If you encounter issues:

1. **Check the error message** - It usually tells you what's wrong
2. **Enable logging** - Set `DeepSeekConfig.enableLogging = true`
3. **Check API status** - Visit https://status.deepseek.com/
4. **Review documentation** - https://platform.deepseek.com/api-docs
5. **Contact DeepSeek support** - Through their platform

---

## ✨ Tips for Best Results

1. **Be specific with topics**
   - Include key concepts, formulas, or themes
   - Example: "Pythagorean theorem, triangle properties, angle calculations"

2. **Match difficulty to grade level**
   - Easy: Basic concepts, definitions
   - Medium: Application, problem-solving
   - Hard: Complex analysis, synthesis

3. **Generate in batches**
   - Generate 5-10 questions at a time
   - Review and regenerate if needed
   - This is more cost-effective than one large batch

4. **Review AI-generated questions**
   - Always review before publishing to students
   - AI is very good but not perfect
   - Edit questions if needed

---

## 🎉 You're All Set!

Your DeepSeek AI integration is now ready to use. Start generating amazing test questions for your students!

**Quick Start:**
1. ✅ Got API key from https://platform.deepseek.com/
2. ✅ Pasted it in `lib/core/config/deepseek_config.dart`
3. ✅ Ran `flutter pub get`
4. ✅ Tested with the AI Test Generator screen

Happy teaching! 🚀
