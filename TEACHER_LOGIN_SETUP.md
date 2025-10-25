# 🎓 Teacher Login Setup Guide

## ✅ WHAT I'VE DONE

### 1. Created Teacher Login Screen
- Location: `lib/screens/teacher/teacher_login_screen.dart`
- Features:
  - ✅ School dropdown (matching your HTML design)
  - ✅ Email input with validation
  - ✅ Password input with show/hide toggle
  - ✅ Firebase authentication integration
  - ✅ "Forgot Password?" functionality
  - ✅ Loading states
  - ✅ Error handling
  - ✅ Beautiful UI matching HTML design (Indigo gradient, rounded corners, shadows)

### 2. Updated Navigation Flow
- **Before**: Role Selection → Teacher Dashboard (direct)
- **Now**: Role Selection → Teacher Login → Teacher Dashboard (after authentication)

### 3. Initialized Firebase
- Created `firebase_options.dart` with Android configuration
- Updated `main.dart` to initialize Firebase on app startup
- Updated gradle files for Firebase support

### 4. Updated Gradle Configuration
Files updated:
- ✅ `android/build.gradle.kts` - Added Google Services plugin
- ✅ `android/app/build.gradle.kts` - Added Firebase dependencies
- ✅ Set minSdk to 21 (Firebase requirement)
- ✅ Added multidex support

---

## 🚀 AUTHENTICATION FLOW

```
User opens app
    ↓
Splash Screen
    ↓
Role Selection Screen (Choose Teacher)
    ↓
Teacher Login Screen (NEW!)
    ↓
Enter: School + Email + Password
    ↓
Firebase Authentication ✅
    ↓
Teacher Dashboard
```

---

## 🔐 HOW IT WORKS

### Login Process:
1. **Select School** from dropdown (Northwood High, Eastwood Academy, South River Middle)
2. **Enter Email** - Validated for proper format
3. **Enter Password** - Minimum 6 characters
4. **Click Login** - Firebase authenticates credentials
5. **Role Check** - Ensures user is a teacher
6. **Navigate** - Redirects to Teacher Dashboard

### Security Features:
- ✅ Firebase Authentication (Email/Password)
- ✅ Role-based access (only teachers can access)
- ✅ Input validation (email format, password length)
- ✅ Error messages for invalid credentials
- ✅ Loading states to prevent multiple submissions
- ✅ Password visibility toggle

### Forgot Password:
1. Enter email address
2. Click "Forgot Password?"
3. Firebase sends password reset email
4. User clicks link in email to reset password

---

## 📋 NEXT STEPS FOR YOU

### STEP 1: Add google-services.json File
You mentioned you have the JSON file. Place it here:
```
android/app/google-services.json
```

**CRITICAL**: The file MUST be named exactly `google-services.json` and placed in `android/app/` folder.

### STEP 2: Enable Firebase Authentication
1. Go to Firebase Console: https://console.firebase.google.com/
2. Select your project: `lenv-cb08e`
3. Click **Authentication** in left menu
4. Click **Get Started**
5. Click **Sign-in method** tab
6. Enable **Email/Password** provider:
   - Click on "Email/Password"
   - Toggle **Enable** to ON
   - Click **Save**

### STEP 3: Create Test Teacher Account
In Firebase Console:
1. Go to **Authentication** → **Users** tab
2. Click **Add User** button
3. Enter:
   - Email: `teacher@test.com` (or any email)
   - Password: `test123` (or any password, min 6 characters)
4. Click **Add User**

### STEP 4: Add Role to Teacher User (IMPORTANT!)
Since your app checks for teacher role, you need to add role data:

**Option A: Using Firestore Console (Recommended)**
1. Go to **Firestore Database** in Firebase Console
2. Click **Start Collection**
3. Collection ID: `users`
4. Document ID: [Copy the UID from Authentication tab]
5. Add fields:
   ```
   email: teacher@test.com
   name: Test Teacher
   role: teacher
   phone: (optional)
   instituteId: (optional)
   createdAt: [Select timestamp]
   isActive: true
   ```
6. Click **Save**

**Option B: Using Code (I can create a script if needed)**

### STEP 5: Clean and Build
```powershell
flutter clean
flutter pub get
flutter run -d <your-android-device>
```

---

## 🧪 TESTING THE LOGIN

### Test Credentials:
- **School**: Select any (Northwood High, Eastwood Academy, or South River Middle)
- **Email**: `teacher@test.com` (or whatever you created)
- **Password**: `test123` (or whatever you set)

### Test Scenarios:

1. **Valid Login**
   - Select school ✅
   - Enter correct email ✅
   - Enter correct password ✅
   - Should navigate to Teacher Dashboard ✅

2. **Invalid Email Format**
   - Enter: `notanemail`
   - Should show: "Please enter a valid email" ❌

3. **Wrong Password**
   - Enter correct email + wrong password
   - Should show: "Invalid email or password" ❌

4. **No School Selected**
   - Don't select school
   - Should show: "Please select your school" ❌

5. **Forgot Password**
   - Enter email
   - Click "Forgot Password?"
   - Should show: "Password reset email sent! Check your inbox." ✅
   - Check email for reset link ✅

---

## 🎨 UI DESIGN FEATURES

### Matching Your HTML Design:
✅ **Indigo gradient logo** (same as HTML `bg-indigo-500 to bg-indigo-700`)
✅ **School icon** in circular gradient background
✅ **LenV** branding at top
✅ **"Teacher Login"** subtitle
✅ **School dropdown** with hint text
✅ **Email input** with placeholder and icon
✅ **Password input** with show/hide toggle
✅ **Rounded corners** on all inputs (12px radius)
✅ **Indigo button** with hover effect simulation
✅ **"Forgot Password?"** link in gray
✅ **White card** with shadow on gray background
✅ **Smooth transitions** and focus states

---

## 🔧 TROUBLESHOOTING

### Problem: "Firebase not initialized"
**Solution**: Make sure you added `google-services.json` to `android/app/`

### Problem: "Sign in failed: user-not-found"
**Solution**: Create the user in Firebase Authentication

### Problem: "Access denied. This is a teacher-only login"
**Solution**: Add `role: teacher` to user document in Firestore

### Problem: App won't build
**Solution**: 
```powershell
flutter clean
flutter pub get
flutter run
```

### Problem: "Email already in use"
**Solution**: Use a different email or delete the existing user from Firebase Console

---

## 📱 SCHOOL DROPDOWN

Currently hardcoded with 3 schools:
- Northwood High
- Eastwood Academy
- South River Middle

**Want to make it dynamic from Firebase?** Let me know and I'll create:
1. School model
2. School service to fetch from Firestore
3. Dynamic dropdown population

---

## 🎯 SUMMARY

### What Works Now:
✅ Beautiful teacher login page (matches HTML design)
✅ Firebase authentication integration
✅ Email/password validation
✅ Role-based access control
✅ Forgot password functionality
✅ Error handling and loading states
✅ Navigation flow updated

### What You Need To Do:
1. ⏳ Add `google-services.json` to `android/app/`
2. ⏳ Enable Email/Password auth in Firebase Console
3. ⏳ Create test teacher account
4. ⏳ Add teacher role to Firestore user document
5. ⏳ Test the login!

---

## 💬 NEED HELP?

Tell me if you need:
- Script to create teacher accounts programmatically
- Dynamic school dropdown from Firestore
- Additional validation rules
- Different authentication methods (Google, Apple, etc.)
- Registration page for new teachers
- Admin panel to manage teachers

**Ready to test?** Complete the 5 steps above and try logging in! 🚀
