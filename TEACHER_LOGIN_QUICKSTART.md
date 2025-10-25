# 🎯 QUICK START - Teacher Login

## ✅ DONE BY ME

✅ Created Teacher Login Screen (matches your HTML design)  
✅ Integrated Firebase Authentication  
✅ Updated navigation flow  
✅ Added forgot password feature  
✅ Configured gradle files  

---

## ⏱️ 5-MINUTE SETUP

### 1️⃣ Add google-services.json (1 min)
```
📁 Place file here:
   android/app/google-services.json
```

### 2️⃣ Enable Email Auth in Firebase (2 min)
1. Open: https://console.firebase.google.com/
2. Select project: **lenv-cb08e**
3. **Authentication** → **Sign-in method**
4. Enable **Email/Password** ✅

### 3️⃣ Create Test Teacher (1 min)
Firebase Console → **Authentication** → **Users**
```
Email: teacher@test.com
Password: test123
```

### 4️⃣ Add Teacher Role (1 min)
Firebase Console → **Firestore Database**
```
Collection: users
Document ID: [UID from Authentication]
Fields:
  - email: teacher@test.com
  - name: Test Teacher
  - role: teacher
  - isActive: true
  - createdAt: [now]
```

### 5️⃣ Build & Test (30 sec)
```powershell
flutter clean
flutter pub get
flutter run -d <device>
```

---

## 🧪 TEST LOGIN

1. Open app
2. Select **Teacher** role
3. Select school: **Northwood High**
4. Email: `teacher@test.com`
5. Password: `test123`
6. Click **Login** ✅
7. Should see: **Teacher Dashboard** 🎉

---

## 🎨 UI FEATURES (FROM YOUR HTML)

✅ Indigo gradient school icon  
✅ LenV branding  
✅ School dropdown (3 schools)  
✅ Email input with validation  
✅ Password with show/hide toggle  
✅ Rounded corners & shadows  
✅ "Forgot Password?" link  
✅ Loading spinner during login  

---

## 🔐 AUTHENTICATION FLOW

```
App Start
   ↓
Splash Screen
   ↓
Role Selection
   ↓
[Click "Teacher"] ← YOU ARE HERE
   ↓
Teacher Login Screen (NEW!)
   ↓
Enter Credentials
   ↓
Firebase Auth ✅
   ↓
Check Role = Teacher
   ↓
Teacher Dashboard 🎉
```

---

## 🚨 IMPORTANT FILES

### Already Updated:
✅ `lib/screens/teacher/teacher_login_screen.dart` (NEW!)  
✅ `lib/firebase_options.dart` (NEW!)  
✅ `lib/main.dart` (Firebase init added)  
✅ `lib/routes/app_router.dart` (Route added)  
✅ `lib/screens/common/role_selection_screen.dart` (Navigation updated)  
✅ `android/build.gradle.kts` (Google services)  
✅ `android/app/build.gradle.kts` (Firebase dependencies)  

### You Need to Add:
⏳ `android/app/google-services.json` (FROM FIREBASE CONSOLE)

---

## 🎯 SCHOOL DROPDOWN

Current schools (hardcoded):
- Northwood High
- Eastwood Academy
- South River Middle

**Want Firestore integration?** I can make it dynamic!

---

## ⚡ ERROR MESSAGES

| Scenario | Message |
|----------|---------|
| No school selected | "Please select your school" |
| Invalid email format | "Please enter a valid email" |
| Wrong password | "Invalid email or password" |
| User not found | "Invalid email or password" |
| Not a teacher | "Access denied. This is a teacher-only login." |

---

## 🔧 IF SOMETHING BREAKS

### Firebase not initialized?
→ Add `google-services.json` to `android/app/`

### User not found?
→ Create user in Firebase Authentication

### Access denied?
→ Add `role: teacher` in Firestore

### Build errors?
```powershell
flutter clean
flutter pub get
```

---

## 📞 WHAT'S NEXT?

After successful login, let me know if you need:

- [ ] Dynamic school list from Firestore
- [ ] Teacher registration page
- [ ] Profile update screen
- [ ] Change password feature
- [ ] Google/Apple sign-in
- [ ] Email verification
- [ ] Remember me feature
- [ ] Biometric authentication

---

## 🎉 READY TO GO!

Follow the 5 steps above → Test login → You're done! ✅

**Questions?** Just ask! 💬
