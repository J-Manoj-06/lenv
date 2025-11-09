# 🎯 Quick Setup: Where to Paste Your DeepSeek API Key

## 📍 STEP-BY-STEP VISUAL GUIDE

### Step 1: Locate the Configuration File

In your project, navigate to:
```
📁 lib
  └── 📁 core
      └── 📁 config
          └── 📄 deepseek_config.dart  ⬅️ OPEN THIS FILE
```

### Step 2: Find the API Key Line

Look for this section (around line 34):

```dart
class DeepSeekConfig {
  // 🔑 PASTE YOUR DEEPSEEK API KEY HERE
  // Example: "sk-1234567890abcdef1234567890abcdef"
  static const String apiKey = "PASTE_YOUR_DEEPSEEK_API_KEY_HERE";  ⬅️ EDIT THIS LINE
                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                        REPLACE THIS PART
```

### Step 3: Replace with Your Actual API Key

**BEFORE (Default):**
```dart
static const String apiKey = "PASTE_YOUR_DEEPSEEK_API_KEY_HERE";
```

**AFTER (With your key):**
```dart
static const String apiKey = "sk-abc123xyz789...";  // Your actual key from DeepSeek
```

### ✅ Complete Example

Here's what the file should look like after you paste your key:

```dart
class DeepSeekConfig {
  // 🔑 PASTE YOUR DEEPSEEK API KEY HERE
  // Example: "sk-1234567890abcdef1234567890abcdef"
  static const String apiKey = "sk-proj-abc123xyz789def456ghi012jkl345mno678pqr901stu234vwx567yza890";
  
  // 🌐 API Configuration
  static const String baseUrl = "https://api.deepseek.com";
  // ... rest of the file stays the same
}
```

---

## 🔐 Where to Get Your API Key

### Method 1: DeepSeek Platform (Recommended)

1. **Visit**: https://platform.deepseek.com/
2. **Sign Up** or **Log In**
3. **Go to**: API Keys section (usually in sidebar or profile menu)
4. **Click**: "Create New API Key" or "Generate API Key"
5. **Copy**: The generated key (it starts with `sk-`)
6. **Paste**: Into the `deepseek_config.dart` file as shown above

### Method 2: Alternative Steps

```
1. Open browser → https://platform.deepseek.com/
2. Create account / Login
3. Dashboard → API Keys
4. Click "New API Key"
5. Copy the key (looks like: sk-xxxxxxxxxxxxxx...)
6. Paste in deepseek_config.dart
```

---

## 🚨 IMPORTANT SECURITY NOTES

### ✅ DO:
- ✅ Keep your API key private
- ✅ Save it in a secure location (password manager)
- ✅ Test with a small number of requests first
- ✅ Monitor your usage on the DeepSeek platform

### ❌ DON'T:
- ❌ Share your API key with anyone
- ❌ Commit it to public GitHub repositories
- ❌ Post it in forums or chat
- ❌ Email it to others

---

## 📱 Model Name & Website URL

Based on your request, here's the information:

### 🤖 Model Name (Default)
```
deepseek-chat
```

**Alternative models you can use:**
- `deepseek-coder` - For programming/technical questions
- `deepseek-reasoner` - For complex reasoning tasks

**How to change the model:**
In `deepseek_config.dart`, edit this line:
```dart
static const String defaultModel = "deepseek-chat";  // Change this if needed
```

### 🌐 Website URL
```
https://platform.deepseek.com/
```

**Other useful URLs:**
- API Documentation: https://platform.deepseek.com/api-docs
- Pricing: https://platform.deepseek.com/pricing
- API Status: https://status.deepseek.com/

---

## 🧪 Testing Your Setup

After pasting your API key, test it:

### Terminal Commands:
```bash
# 1. Install dependencies
flutter pub get

# 2. Run your app
flutter run
```

### In Your App:
1. Log in as a **Teacher**
2. Go to **AI Test Generator** screen
3. Fill in:
   - Subject: "Mathematics"
   - Topics: "Algebra, Linear Equations"
   - Questions: "5"
   - Difficulty: "Medium"
4. Click **"Generate"**
5. Wait 5-10 seconds
6. ✅ You should see AI-generated questions!

---

## ⚠️ Troubleshooting

### Error: "DeepSeek API not configured"
**Solution**: You haven't replaced `PASTE_YOUR_DEEPSEEK_API_KEY_HERE` yet. Go back to Step 2 above.

### Error: "Failed to generate questions"
**Solution**: 
- Double-check your API key is correct (copy it again from DeepSeek)
- Make sure you have internet connection
- Verify your API key has remaining quota on the DeepSeek platform

### Questions don't appear after clicking Generate
**Solution**:
1. Check the terminal/console for error messages
2. Make sure you saved the `deepseek_config.dart` file after editing
3. Hot restart the app (press 'R' in terminal or restart from IDE)

---

## 📞 Need Help?

1. **Check the detailed guide**: See `DEEPSEEK_SETUP.md` in your project root
2. **Review error messages**: Look at the terminal output
3. **DeepSeek Support**: Visit https://platform.deepseek.com/ and contact support
4. **API Documentation**: https://platform.deepseek.com/api-docs

---

## ✨ Summary Checklist

Before you start, make sure:

- [ ] You have a DeepSeek account (https://platform.deepseek.com/)
- [ ] You've created an API key on the platform
- [ ] You've copied the API key (starts with `sk-`)
- [ ] You've opened `lib/core/config/deepseek_config.dart`
- [ ] You've replaced `PASTE_YOUR_DEEPSEEK_API_KEY_HERE` with your actual key
- [ ] You've saved the file
- [ ] You've run `flutter pub get`
- [ ] You've hot restarted your app

**Once all checkboxes are ticked, you're ready to generate AI test questions!** 🎉

---

**Pro Tip**: After testing, you can customize the AI behavior by editing other settings in `deepseek_config.dart` like temperature, max tokens, etc. See `DEEPSEEK_SETUP.md` for details.
