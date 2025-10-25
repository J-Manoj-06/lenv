# 📱 Android Firebase Setup - COMPLETE GUIDE

## 🎯 Overview

This app is **Android-only**. Follow these steps to set up Firebase for Android.

---

## 📋 STEP 1: Register Android App in Firebase (5 minutes)

### 1.1: Go to Firebase Console
1. Open: https://console.firebase.google.com/
2. Select your project
3. Click ⚙️ (Project Settings) in the left sidebar

### 1.2: Add Android App
1. Scroll to "Your apps" section
2. Click **"Add app"** button
3. Choose **Android** icon (robot icon)

### 1.3: Enter App Details
**Package name:** `com.lenv.new_reward`
   - ⚠️ **CRITICAL:** Must match exactly!
   - This comes from `android/app/build.gradle.kts`
   - Default is: `com.lenv.new_reward`

**App nickname:** `LenV Android` (or any name you want)

**Debug signing certificate SHA-1:** (Optional for now - skip)

4. Click **"Register app"**

---

## 📋 STEP 2: Download google-services.json (2 minutes)

### 2.1: Download the File
1. After registering, Firebase shows a download button
2. Click **"Download google-services.json"**
3. Save the file (remember where!)

### 2.2: Place in Correct Location
**CRITICAL:** File must go in the RIGHT place!

✅ **CORRECT Location:**
```
new_reward/
└── android/
    └── app/
        └── google-services.json  ← HERE!
```

❌ **WRONG Location:**
```
new_reward/
└── android/
    └── google-services.json  ← NOT HERE!
```

### 2.3: How to Add It
1. In VS Code, open Explorer
2. Navigate to: `android/app/`
3. Copy your downloaded `google-services.json`
4. Paste it into `android/app/` folder
5. Verify filename is exactly: `google-services.json`

---

## 📋 STEP 3: Update Android Build Files (10 minutes)

### 3.1: Update Project-Level build.gradle.kts

**File:** `android/build.gradle.kts`

Find the `dependencies` block and add Google Services:

```kotlin
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.0")
        classpath("com.google.gms:google-services:4.4.0")  // ← ADD THIS LINE
    }
}
```

### 3.2: Update App-Level build.gradle.kts

**File:** `android/app/build.gradle.kts`

**Add plugin at TOP (after other plugins):**
```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")  // ← ADD THIS LINE
}
```

**Add Firebase dependencies at BOTTOM:**
```kotlin
dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    
    // Firebase BOM (Bill of Materials) - manages versions
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    
    // Firebase dependencies (versions managed by BOM)
    implementation("com.google.firebase:firebase-analytics-ktx")
    implementation("com.google.firebase:firebase-auth-ktx")
    implementation("com.google.firebase:firebase-firestore-ktx")
    implementation("com.google.firebase:firebase-storage-ktx")
}
```

---

## 📋 STEP 4: Update firebase_config.dart (5 minutes)

**File:** `lib/core/config/firebase_config.dart`

You can find these values by opening `google-services.json` in a text editor:

```json
{
  "client": [
    {
      "api_key": [
        {
          "current_key": "AIza..."  ← androidApiKey
        }
      ],
      "client_info": {
        "mobilesdk_app_id": "1:123:android:abc"  ← androidAppId
      }
    }
  ],
  "project_info": {
    "project_id": "your-project",  ← androidProjectId
    "project_number": "123456",    ← androidMessagingSenderId
    "storage_bucket": "xxx.appspot.com"  ← androidStorageBucket
  }
}
```

**Update these values in firebase_config.dart:**
```dart
static const String androidApiKey = "AIza...";  // from current_key
static const String androidProjectId = "your-project-id";  // from project_id
static const String androidStorageBucket = "xxx.appspot.com";  // from storage_bucket
static const String androidMessagingSenderId = "123456";  // from project_number
static const String androidAppId = "1:123:android:abc";  // from mobilesdk_app_id
```

---

## 📋 STEP 5: Clean and Rebuild (2 minutes)

1. Go to Firebase Console: https://console.firebase.google.com/
2. Select your project
3. Click ⚙️ (Project Settings)
4. Scroll to "Your apps" section
5. Click **"Add app"** button
6. Choose **Android** icon
7. Enter package name: `com.lenv.new_reward`
   - ⚠️ Must match exactly! Check `android/app/build.gradle.kts`
8. Enter app nickname: `LenV Android`
9. Click **"Register app"**

---

### Step 2: Download google-services.json

1. After registering, Firebase will show download button
2. Click **"Download google-services.json"**
3. Save the file (remember where you saved it!)

---

### Step 3: Place google-services.json in Your Project

**IMPORTANT:** The file must go in the correct location!

**Correct location:**
```
new_reward/
└── android/
    └── app/
        └── google-services.json  ← HERE!
```

**NOT here:**
```
new_reward/
└── android/
    └── google-services.json  ← WRONG! Not in root android folder
```

**How to add it:**
1. Open VS Code
2. In Explorer, navigate to: `android/app/`
3. Copy your downloaded `google-services.json` file
4. Paste it in `android/app/` folder
5. Verify the file name is exactly: `google-services.json`

---

### Step 4: Update Android Configuration Files

#### File 1: android/build.gradle.kts (Project level)

**Add Google Services plugin:**

Find the `dependencies` section and add:
```kotlin
dependencies {
    classpath("com.android.tools.build:gradle:8.1.0")
    classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.0")
    classpath("com.google.gms:google-services:4.4.0")  // ← ADD THIS LINE
}
```

#### File 2: android/app/build.gradle.kts (App level)

**Add plugin at the TOP of the file (after existing plugins):**
```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")  // ← ADD THIS LINE
}
```

**Add dependencies at the BOTTOM (inside dependencies block):**
```kotlin
dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    
    // Firebase dependencies
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-storage")
}
```

---

### Step 5: Update firebase_config.dart

Open `lib/core/config/firebase_config.dart` and update Android values:

```dart
// 🔴 ANDROID CONFIGURATION
static const String androidApiKey = "YOUR_ANDROID_API_KEY";
static const String androidAppId = "YOUR_ANDROID_APP_ID";
```

**Where to find these values:**
- Firebase Console → Project Settings
- Find your Android app
- Look for the config or download `google-services.json`
- Open `google-services.json` in text editor:
  - `androidApiKey` = value from `"api_key"` field
  - `androidAppId` = value from `"mobilesdk_app_id"` field

---

## 📁 File Structure After Setup

```
new_reward/
├── android/
│   ├── build.gradle.kts         (updated)
│   └── app/
│       ├── build.gradle.kts     (updated)
│       └── google-services.json (NEW - added by you)
│
└── lib/
    └── core/
        └── config/
            └── firebase_config.dart (updated with Android values)
```

---

## ✅ Verification Checklist

- [ ] Registered Android app in Firebase Console
- [ ] Downloaded google-services.json
- [ ] Placed google-services.json in `android/app/` folder
- [ ] Updated `android/build.gradle.kts` (added Google Services plugin)
- [ ] Updated `android/app/build.gradle.kts` (added plugin and dependencies)
- [ ] Updated `firebase_config.dart` with Android values
- [ ] Ran `flutter clean`
- [ ] Ran `flutter pub get`

---

## 🧪 Test Android Setup

Run these commands:

```bash
# Clean the project
flutter clean

# Get dependencies
flutter pub get

# Run on Android device/emulator
flutter run -d android
```

If you see errors, check:
- google-services.json is in correct location
- Package name matches in all files
- All gradle files have correct syntax

---

## ⚠️ Common Issues

### "google-services.json not found"
→ Make sure file is in `android/app/` not `android/`

### "Failed to apply plugin"
→ Check `build.gradle.kts` syntax is correct

### "Package name mismatch"
→ Package name in Firebase must match `applicationId` in `android/app/build.gradle.kts`

---

## 🎯 REMEMBER

**You DON'T need to do this right now!**

Focus on:
1. ✅ Complete Web configuration first
2. ✅ Test the app on Chrome
3. ✅ Make sure dashboard works

Then come back to Android setup later if needed.

---

## 💬 When You're Done

If you complete Android setup, tell me:
```
"✅ Android setup complete! google-services.json added and gradle files updated"
```

Otherwise, just focus on Web for now! 😊
