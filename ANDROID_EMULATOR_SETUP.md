# ⚠️ ANDROID EMULATOR SETUP REQUIRED

## 🚨 THE ERROR EXPLAINED

You tried to run the app on **Chrome (Web)**, but:
- ❌ Firebase is configured for **Android ONLY**
- ❌ Web configuration is NOT included
- ✅ You said: "this app is only for android"

**The error message:**
```
DartError: Unsupported operation: DefaultFirebaseOptions have not been 
configured for web - you can reconfigure this by running the FlutterFire CLI again.
```

This is **CORRECT BEHAVIOR** - the app is blocking web access as intended!

---

## 🎯 SOLUTION: Run on Android Device

You have **3 options**:

### Option 1: Use Android Emulator (Your Current Setup)

Your emulator `Pixel_6_API_30` shows as "unsupported" (API 30 / Android 11).

**To fix this:**

1. **Open Android Studio**
2. Go to **Tools** → **Device Manager** (or AVD Manager)
3. Find your **Pixel 6 API 30** emulator
4. Click ⚙️ **Edit**
5. Update to a newer API level (API 33 or 34 recommended)
   
**OR create a new emulator:**
```powershell
# In Android Studio:
# Tools → Device Manager → Create Device
# Choose: Pixel 6
# System Image: API 33 or 34 (Android 13/14)
# Finish
```

Then launch and run:
```powershell
flutter emulators --launch <new-emulator-name>
flutter run
```

---

### Option 2: Connect Physical Android Device

1. **Enable Developer Options** on your Android phone:
   - Settings → About Phone
   - Tap "Build Number" 7 times
   - You'll see "You are now a developer!"

2. **Enable USB Debugging**:
   - Settings → Developer Options
   - Toggle "USB Debugging" ON

3. **Connect via USB**:
   - Plug phone into computer
   - Allow debugging prompt on phone
   - Run: `flutter devices`
   - Should see your phone listed

4. **Run app**:
   ```powershell
   flutter run
   ```

---

### Option 3: Run Without Firebase (Testing Only)

If you just want to test the UI without Firebase authentication:

**Temporarily disable Firebase:**

I can modify `main.dart` to skip Firebase initialization when running on web, so you can see the UI. But **login won't work** without Firebase.

---

## 🔧 RECOMMENDED: Fix Your Emulator

### Steps to update emulator in Android Studio:

1. **Open Android Studio**
2. **Tools** → **Device Manager**
3. **Look for**: "Pixel 6 API 30"
4. **Click**: ⚙️ (Edit icon)
5. **Change API Level**: 
   - Current: API 30 (Android 11) ❌
   - Change to: API 33 or API 34 (Android 13/14) ✅
6. **Click**: "Download" if needed
7. **Click**: "Finish"
8. **Launch**: Start the emulator
9. **Run app**:
   ```powershell
   flutter run
   ```

---

## 📱 ALTERNATIVE: Create New Emulator

If editing doesn't work, create a fresh one:

### In Android Studio:
1. **Tools** → **Device Manager**
2. **Create Device** button
3. **Select Hardware**: Pixel 6 or Pixel 7
4. **System Image**: 
   - Click "Download" next to API 33 or 34
   - Wait for download
   - Select it
5. **AVD Name**: Give it a name (e.g., "Pixel_6_API_33")
6. **Finish**
7. **Launch** the new emulator
8. **Run app**: `flutter run`

---

## 🚀 ONCE EMULATOR IS READY

After you have a working Android emulator:

```powershell
# 1. Make sure emulator is running
flutter devices
# Should see something like:
#   Pixel 6 API 33 (mobile) • emulator-5554 • android-arm64 • Android 13 (API 33)

# 2. Run the app
flutter run

# Or specify the device:
flutter run -d emulator-5554
```

---

## ⚠️ IMPORTANT: Don't Run on Web!

**This app is Android-only.**

If you accidentally run `flutter run -d chrome`, you'll see the error you just saw.

**Always use:**
```powershell
flutter run              # Auto-selects Android if available
# OR
flutter run -d emulator-5554    # Specific Android device
```

**Never use:**
```powershell
flutter run -d chrome    # ❌ Will fail - no web config
flutter run -d edge      # ❌ Will fail - no web config
flutter run -d windows   # ❌ Desktop not configured
```

---

## 📋 CHECKLIST

Before running the app, make sure:

- [ ] Android emulator is created (API 33+ recommended)
- [ ] Emulator is running (`flutter devices` shows it)
- [ ] `google-services.json` is in `android/app/`
- [ ] Firebase Email/Password auth is enabled
- [ ] Test teacher account exists in Firebase
- [ ] Teacher has `role: "teacher"` in Firestore

Then:
```powershell
flutter clean
flutter pub get
flutter run
```

---

## 🎓 SUMMARY

**Your Error**: Tried to run Android-only app on Web (Chrome)  
**The Fix**: Run on Android device or emulator  
**Current Issue**: Your emulator API 30 is unsupported  
**Solution**: Update to API 33/34 or create new emulator  

---

## 💬 NEED HELP?

Tell me which option you want:

1. **I'll use physical Android phone** → I'll guide you through USB setup
2. **I want to fix my emulator** → I'll help with Android Studio steps
3. **I want to test UI on web** → I'll disable Firebase temporarily (login won't work)
4. **I don't have Android Studio** → I'll help you install it

**What do you prefer?** 📱
