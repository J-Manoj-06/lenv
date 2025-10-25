# 🔥 Firebase Configuration Instructions

## 📍 WHERE TO FIND YOUR FIREBASE VALUES

### Step 1: Go to Firebase Console
1. Open: https://console.firebase.google.com/
2. Select your project
3. Click the **⚙️ gear icon** (Project Settings) in the left sidebar

### Step 2: Find Your Web App Config
1. Scroll down to **"Your apps"** section
2. You should see your Web app (with `</>` icon)
3. Click on it or scroll down to see **"SDK setup and configuration"**
4. Select **"Config"** radio button (not npm)
5. You'll see something like this:

```javascript
const firebaseConfig = {
  apiKey: "AIzaSyAbc123XyZ456...",
  authDomain: "your-project.firebaseapp.com",
  projectId: "your-project-id",
  storageBucket: "your-project.appspot.com",
  messagingSenderId: "123456789012",
  appId: "1:123456789012:web:abc123def456"
};
```

### Step 3: Copy Values to firebase_config.dart
Open the file: `lib/core/config/firebase_config.dart` and replace:

- `PASTE_YOUR_API_KEY_HERE` → with your `apiKey` value
- `PASTE_YOUR_AUTH_DOMAIN_HERE` → with your `authDomain` value
- `PASTE_YOUR_PROJECT_ID_HERE` → with your `projectId` value
- `PASTE_YOUR_STORAGE_BUCKET_HERE` → with your `storageBucket` value
- `PASTE_YOUR_MESSAGING_SENDER_ID_HERE` → with your `messagingSenderId` value
- `PASTE_YOUR_APP_ID_HERE` → with your `appId` value

---

## 📱 FOR ANDROID (google-services.json)

### If you've created an Android app in Firebase:

1. In Firebase Console → Project Settings → Your apps
2. Find your Android app
3. Click **"Download google-services.json"**
4. **Place the file here:** `android/app/google-services.json`

⚠️ **IMPORTANT:** The file must be in `android/app/` folder, NOT in `android/` root!

---

## 🍎 FOR iOS (GoogleService-Info.plist)

### If you've created an iOS app in Firebase:

1. In Firebase Console → Project Settings → Your apps
2. Find your iOS app
3. Click **"Download GoogleService-Info.plist"**
4. **Place the file here:** `ios/Runner/GoogleService-Info.plist`

---

## ✅ VERIFICATION

After pasting your values, the file should look like:

```dart
static const String webApiKey = "AIzaSyAbc123XyZ456...";  // ✅ Real value
static const String webAuthDomain = "my-project.firebaseapp.com";  // ✅ Real value
static const String webProjectId = "my-project-id";  // ✅ Real value
```

NOT like this:
```dart
static const String webApiKey = "PASTE_YOUR_API_KEY_HERE";  // ❌ Still placeholder
```

---

## 🔐 SECURITY NOTE

⚠️ This file contains sensitive API keys. 

**For production apps:**
- Add `firebase_config.dart` to `.gitignore`
- Use environment variables
- Enable Firebase security rules

**For development:**
- It's okay to commit with test mode rules
- Make sure Firestore rules are in test mode

---

## ❓ COMMON ISSUES

### "I don't see the config values"
→ Make sure you've registered a Web app in Firebase Console
→ Go to Project Settings → Scroll to "Your apps" → Click "Add app" → Choose Web

### "I can't find my google-services.json"
→ You need to register an Android app first
→ Go to Project Settings → Add app → Choose Android
→ Enter package name: `com.lenv.new_reward`

### "Where do I get the iOS config?"
→ Register an iOS app in Firebase Console
→ Enter bundle ID: `com.lenv.newReward`

---

## ✨ DONE?

Once you've pasted all Web values, let me know and I'll:
1. ✅ Create all required model files
2. ✅ Create Firebase services
3. ✅ Create providers for state management
4. ✅ Update main.dart to initialize Firebase
5. ✅ Make your dashboard dynamic
6. ✅ Add sample data loader

**Message me:** "✅ Firebase config pasted! Ready for next step"
