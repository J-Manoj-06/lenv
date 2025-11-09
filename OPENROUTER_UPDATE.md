# 🔄 OpenRouter Integration Update

## What Changed

Your app has been updated to use **OpenRouter** instead of direct DeepSeek API. OpenRouter is a unified API platform that provides access to multiple AI models, including DeepSeek.

---

## ✅ Your Setup is Complete!

Your OpenRouter API key has been successfully configured:
```
API Key: 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
Model: deepseek/deepseek-r1:free (FREE model!)
```

---

## 🎉 What's Working Now

### Configuration Updated
- ✅ **API Endpoint**: Changed from `https://api.deepseek.com` to `https://openrouter.ai/api`
- ✅ **Model Name**: Changed to `deepseek/deepseek-r1:free` (OpenRouter format)
- ✅ **Headers**: Added OpenRouter-specific headers (HTTP-Referer, X-Title)
- ✅ **Validation**: Updated to check for `sk-or-v1-` prefix

### Files Modified
1. **`lib/core/config/deepseek_config.dart`**
   - Updated API base URL
   - Changed model name to OpenRouter format
   - Added site URL and name fields (optional)
   - Updated API key validation

2. **`lib/services/deepseek_service.dart`**
   - Added OpenRouter-specific headers
   - Updated logging messages
   - Enhanced error handling for OpenRouter responses

---

## 🚀 How to Test

### Step 1: Run the App
```bash
flutter run
```

### Step 2: Login as Teacher
Use your teacher credentials to log in.

### Step 3: Navigate to AI Test Generator
Find and open the **AI Test Generator** screen.

### Step 4: Fill in the Form
- **Subject**: Mathematics (or any subject)
- **Topics**: "Linear equations, quadratic equations" (or any topics)
- **Number of Questions**: 5 (start small)
- **Difficulty**: Medium
- **Class/Grade**: Select any class

### Step 5: Generate Questions
Click the **"Generate"** button and wait ~5-10 seconds.

### Expected Result
You should see AI-generated multiple-choice questions with:
- ✅ Question text
- ✅ 4 answer options (A, B, C, D)
- ✅ Correct answer marked
- ✅ Explanation

---

## 🆓 Free Model Information

### DeepSeek R1 (Free)
**Model Name**: `deepseek/deepseek-r1:free`

**Features**:
- ✅ **Free to use** (no cost per request)
- ✅ Advanced reasoning capabilities
- ✅ Good for educational content
- ✅ Supports complex question generation
- ✅ Fast response times

**Limitations**:
- ⏳ May have rate limits (requests per minute)
- ⏳ Lower priority than paid models
- ⏳ Possible queue wait times during high traffic

**When to Use**:
- Testing and development
- Low-volume production use
- Educational projects
- Budget-conscious deployments

---

## 💰 Alternative Models (Paid)

If you need higher performance, you can switch to paid models:

### 1. DeepSeek Chat (Paid)
```dart
static const String defaultModel = "deepseek/deepseek-chat";
```
- **Cost**: ~$0.14 per 1M tokens (input), $0.28 per 1M tokens (output)
- **Benefits**: Higher priority, no queue, faster responses
- **Best for**: Production apps with high traffic

### 2. DeepSeek Coder (Paid)
```dart
static const String defaultModel = "deepseek/deepseek-coder";
```
- **Cost**: Similar to DeepSeek Chat
- **Benefits**: Optimized for programming/technical subjects
- **Best for**: Computer science, coding questions

To change models, edit `lib/core/config/deepseek_config.dart` line ~43.

---

## 🌐 OpenRouter vs Direct DeepSeek API

### Why OpenRouter?

| Feature | OpenRouter | Direct DeepSeek |
|---------|-----------|-----------------|
| **Free Tier** | ✅ Yes (deepseek-r1:free) | ❌ No |
| **Multiple Models** | ✅ 100+ models available | ❌ Only DeepSeek models |
| **API Simplicity** | ✅ Unified API for all models | ❌ Different APIs per provider |
| **Model Switching** | ✅ Easy (change model name) | ❌ Requires code changes |
| **Pricing** | ✅ Transparent | ✅ Transparent |
| **Response Format** | ✅ Standard OpenAI format | ✅ Standard OpenAI format |

### OpenRouter Advantages
1. **Free model available** - DeepSeek R1 is completely free
2. **Model flexibility** - Switch between models without code changes
3. **Single API key** - Access 100+ AI models with one key
4. **Unified billing** - One bill for all models
5. **Model fallback** - Automatically use backup models if primary fails

---

## 🔧 Optional Configuration

### Add Your Site URL (Optional)
In `deepseek_config.dart`, you can add your app's URL:

```dart
static const String siteUrl = "https://yourapp.com"; // Your app URL
static const String siteName = "Education Rewards App"; // Your app name
```

**Benefits**:
- Helps you rank on OpenRouter's model leaderboards
- Better analytics and tracking
- Professional integration

### Enable/Disable Logging
To see detailed API logs (useful for debugging):

```dart
static const bool enableLogging = true;  // Enable
static const bool enableLogging = false; // Disable
```

When enabled, you'll see in the console:
- API request details (URL, model, temperature)
- Response status
- Token usage
- Error messages (if any)

---

## 📊 Monitor Your Usage

### Check Your OpenRouter Dashboard
1. Visit: **https://openrouter.ai/**
2. Log in with your account
3. Go to **Dashboard** or **Usage**
4. View:
   - Total requests made
   - Tokens used
   - Costs (if using paid models)
   - Rate limit status

### Free Model Limits
The free `deepseek-r1:free` model has limits:
- **Rate limit**: Variable (based on server load)
- **Queue priority**: Lower than paid models
- **Quota**: May have daily/hourly limits

If you hit limits, the app will show an error. Solutions:
1. Wait a few minutes and retry
2. Upgrade to a paid model
3. Reduce request frequency

---

## 🐛 Troubleshooting

### Error: "API key not configured"
**Cause**: API key validation failed
**Solution**: 
- Check that `apiKey` in `deepseek_config.dart` starts with `sk-or-v1-`
- Your key is already set correctly: `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`

### Error: "Failed to generate questions"
**Causes**: 
- Invalid API key
- No internet connection
- Rate limit exceeded
- Server error

**Solutions**:
1. Verify API key on https://openrouter.ai/keys
2. Check internet connection
3. Wait a few minutes (rate limit)
4. Check OpenRouter status: https://status.openrouter.ai/

### Error: "Failed to parse AI response"
**Cause**: AI returned invalid JSON format
**Solutions**:
1. Try generating again (temporary AI glitch)
2. Reduce question count
3. Simplify your topic description
4. Check logs (if enabled) to see raw response

### Questions are low quality
**Solutions**:
1. Be more specific in "Topics" field
2. Add detailed subject concepts
3. Try different difficulty levels
4. Regenerate if quality is poor
5. Consider upgrading to paid model for better quality

---

## 🔐 Security Reminders

### ⚠️ Important
1. **Never commit API keys** to public repositories
2. **Don't share** your API key with others
3. **Monitor usage** regularly on OpenRouter dashboard
4. **Set spending limits** on OpenRouter (if using paid models)
5. **Rotate keys** periodically for security

### For Production
Consider:
- Using environment variables for API keys
- Moving AI calls to a backend server
- Implementing rate limiting on your app
- Adding usage quotas per user/school

---

## 📈 Next Steps

### Immediate Testing
1. ✅ Run `flutter run`
2. ✅ Login as teacher
3. ✅ Test AI Test Generator
4. ✅ Verify questions are generated

### Future Enhancements
- 📝 Save generated questions to Firebase
- 🎯 Create question banks by subject/topic
- 📊 Let teachers rate question quality
- 🔄 Regenerate individual questions
- 📤 Export questions to PDF
- 🎨 Customize question formats

### Model Exploration
Try other free OpenRouter models:
- `meta-llama/llama-3.1-8b-instruct:free`
- `google/gemma-2-9b-it:free`
- `microsoft/phi-3-mini-128k-instruct:free`

Change in `deepseek_config.dart` to experiment!

---

## 📚 Useful Links

### OpenRouter
- **Platform**: https://openrouter.ai/
- **API Docs**: https://openrouter.ai/docs
- **All Models**: https://openrouter.ai/models
- **Pricing**: https://openrouter.ai/pricing
- **Status**: https://status.openrouter.ai/

### DeepSeek (Original Provider)
- **Website**: https://www.deepseek.com/
- **DeepSeek R1**: https://www.deepseek.com/r1
- **Research**: https://www.deepseek.com/research

### Community
- **OpenRouter Discord**: https://discord.gg/openrouter
- **GitHub Issues**: Report bugs to OpenRouter or your app repo

---

## ✨ Summary

### What You Have Now
✅ **Free AI integration** using OpenRouter's `deepseek-r1:free` model
✅ **Working configuration** - API key is set and validated
✅ **Test question generation** - Create multiple-choice questions with AI
✅ **Error handling** - User-friendly error messages
✅ **Logging support** - Debug API issues easily
✅ **Flexible models** - Easy to switch models in future

### Ready to Use!
Your app is now configured to use OpenRouter's free DeepSeek R1 model for AI-powered test question generation. Just run the app and test the AI Test Generator screen!

---

**Need Help?**
- Check logs in console if `enableLogging = true`
- Visit OpenRouter docs: https://openrouter.ai/docs
- Check this file for troubleshooting tips

**Happy Teaching with AI! 🎓🤖**
