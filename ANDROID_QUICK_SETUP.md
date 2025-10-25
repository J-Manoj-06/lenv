# ✅ ANDROID ONLY - Quick Setup Checklist

## 🎯 THIS APP IS FOR ANDROID ONLY

Follow these steps in order:

---

## 📋 STEP 1: Firebase Console Setup (10 minutes)

### ☐ 1.1: Register Android App
1. Go to: https://console.firebase.google.com/
2. Select your project
3. Click ⚙️ (Project Settings)
4. Click "Add app" → Choose Android
5. **Package name:** `com.lenv.new_reward` (CRITICAL - must match!)
6. **App nickname:** `LenV Android`
7. Click "Register app"

### ☐ 1.2: Download google-services.json
1. Click "Download google-services.json"
2. Save the file

### ☐ 1.3: Enable Firebase Services
1. **Authentication:** Enable Email/Password
2. **Firestore Database:** Create in test mode
3. **Storage:** Enable in test mode

---

## 📋 STEP 2: Add Files to Your Project (5 minutes)

### ☐ 2.1: Add google-services.json
**CRITICAL:** Must be in correct location!

✅ **Correct:** `android/app/google-services.json`
❌ **Wrong:** `android/google-services.json`

**How:**
1. In VS Code, open `android/app/` folder
2. Copy your downloaded `google-services.json`
3. Paste it there
4. Verify filename: `google-services.json`

### ☐ 2.2: Update firebase_config.dart
**File:** `lib/core/config/firebase_config.dart`

**Open google-services.json in text editor, find these values:**
```json
{
  "client": [{
    "api_key": [{"current_key": "AIza..."}],  ← androidApiKey
    "client_info": {
      "mobilesdk_app_id": "1:123:android:abc"  ← androidAppId
    }
  }],
  "project_info": {
    "project_id": "your-project",      ← androidProjectId
    "project_number": "123456",        ← androidMessagingSenderId
    "storage_bucket": "xxx.appspot.com" ← androidStorageBucket
  }
}
```

**Paste into firebase_config.dart:**
```dart
static const String androidApiKey = "AIza...";
static const String androidProjectId = "your-project";
static const String androidStorageBucket = "xxx.appspot.com";
static const String androidMessagingSenderId = "123456";
static const String androidAppId = "1:123:android:abc";
```

---

## 📋 STEP 3: Update Gradle Files (10 minutes)

### ☐ 3.1: Update android/build.gradle.kts

**Add this line in dependencies section:**
```kotlin
buildscript {
    dependencies {
        // ... existing dependencies
        classpath("com.google.gms:google-services:4.4.0")  // ADD THIS
    }
}
```

### ☐ 3.2: Update android/app/build.gradle.kts

**At TOP (after existing plugins):**
```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")  // ADD THIS
}
```

**At BOTTOM (in dependencies):**
```kotlin
dependencies {
    // ... existing dependencies
    
    // Firebase dependencies
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-analytics-ktx")
    implementation("com.google.firebase:firebase-auth-ktx")
    implementation("com.google.firebase:firebase-firestore-ktx")
    implementation("com.google.firebase:firebase-storage-ktx")
}
```

---

## 📋 STEP 4: Build & Test (5 minutes)

### ☐ 4.1: Clean and Build
```bash
flutter clean
flutter pub get
flutter build apk --debug
```

**Expected:** Build succeeds without errors

### ☐ 4.2: Run on Device
```bash
flutter devices
flutter run
```

**Expected:** App launches successfully

---

## ✅ VERIFICATION CHECKLIST

Before saying you're done, verify:

### Files Added:
- [ ] `android/app/google-services.json` exists
- [ ] `lib/core/config/firebase_config.dart` updated with Android values

### Files Modified:
- [ ] `android/build.gradle.kts` has Google Services plugin
- [ ] `android/app/build.gradle.kts` has plugin and Firebase dependencies

### Firebase Console:
- [ ] Android app registered
- [ ] Authentication enabled (Email/Password)
- [ ] Firestore created (test mode)
- [ ] Storage enabled (test mode)

### Testing:
- [ ] `flutter clean` ran successfully
- [ ] `flutter pub get` ran successfully
- [ ] `flutter build apk --debug` succeeded
- [ ] App runs on Android device/emulator

---

## 💬 WHEN YOU'RE DONE

Tell me:
```
✅ Android setup complete! All steps done. Ready for next phase.
```

Then I'll create:
- ✅ All data models (5 files)
- ✅ Firebase services (1 file)
- ✅ State management providers (1 file)
- ✅ Update main.dart for Firebase init
- ✅ Make dashboard dynamic
- ✅ Add sample data loader

---

## ⏱️ TIME ESTIMATE

- Step 1: 10 minutes (Firebase Console)
- Step 2: 5 minutes (Add files)
- Step 3: 10 minutes (Update gradle)
- Step 4: 5 minutes (Build & test)
- **TOTAL: ~30 minutes**

---

## 🆘 HELP

### "Where do I find google-services.json values?"
→ Open the file in any text editor (Notepad, VS Code)
→ Look for the fields shown in Step 2.2

### "Build failing?"
→ Make sure google-services.json is in `android/app/`
→ Check package name matches everywhere
→ Run `flutter clean` then rebuild

### "Can't find gradle files?"
→ `android/build.gradle.kts` (project level)
→ `android/app/build.gradle.kts` (app level)

### "Still stuck?"
→ Tell me which step you're on
→ Share the error message
→ I'll help you fix it!

---

## 🚀 START HERE

1. Open: https://console.firebase.google.com/
2. Follow Step 1
3. Download google-services.json
4. Follow remaining steps
5. Tell me when done!

**Let's do this! 💪**
