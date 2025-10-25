# 🔥 Firebase Integration & Dynamic Dashboard - Complete Implementation Plan

## 📋 Overview
This document provides a step-by-step guide to integrate Firebase into your Flutter app and make the Teacher Dashboard dynamic with real-time data from Firestore.

---

## 🎯 PHASE 1: Firebase Project Setup (30 minutes)

### Step 1.1: Create Firebase Project
1. **Go to Firebase Console**: https://console.firebase.google.com/
2. **Click "Add project"** or "Create a project"
3. **Enter project name**: `lenv-educational-app` (or your preferred name)
4. **Disable Google Analytics** (optional, can enable later)
5. **Click "Create project"** and wait for it to be created
6. **Click "Continue"** when done

### Step 1.2: Register Your Flutter App with Firebase

#### For Web (Chrome):
1. In Firebase Console, click the **Web icon** (`</>`) on the project homepage
2. **App nickname**: `LenV Web App`
3. **Check** "Also set up Firebase Hosting" (optional)
4. Click **"Register app"**
5. **IMPORTANT**: Copy the `firebaseConfig` object shown - you'll need these values:
   ```javascript
   const firebaseConfig = {
     apiKey: "AIza...",              // Copy this
     authDomain: "xxx.firebaseapp.com",
     projectId: "xxx",
     storageBucket: "xxx.appspot.com",
     messagingSenderId: "123456",
     appId: "1:123456:web:abc123"    // Copy this
   };
   ```
6. Click **"Continue to console"**

#### For Android (Future):
1. Click **Android icon** on Firebase project homepage
2. **Android package name**: `com.lenv.new_reward` (from `android/app/build.gradle.kts`)
3. **Download** `google-services.json`
4. **Place it in**: `android/app/google-services.json`
5. Add dependencies to `android/build.gradle.kts` (provided later)

#### For iOS (Future):
1. Click **iOS icon** on Firebase project homepage
2. **iOS bundle ID**: `com.lenv.newReward` (from `ios/Runner.xcodeproj`)
3. **Download** `GoogleService-Info.plist`
4. **Place it in**: `ios/Runner/GoogleService-Info.plist`
5. Add to Xcode project (drag into Runner folder in Xcode)

---

## 🔐 PHASE 2: Enable Firebase Services (15 minutes)

### Step 2.1: Enable Authentication
1. In Firebase Console, go to **"Authentication"** → **"Get started"**
2. Click **"Sign-in method"** tab
3. **Enable "Email/Password"**:
   - Toggle on "Email/Password"
   - Click "Save"
4. (Optional) Enable **Google Sign-In** for future use

### Step 2.2: Create Firestore Database
1. Go to **"Firestore Database"** → **"Create database"**
2. **Choose mode**: Select **"Start in test mode"** (for development)
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /{document=**} {
         allow read, write: if request.time < timestamp.date(2025, 12, 31);
       }
     }
   }
   ```
3. **Select location**: Choose closest to your users (e.g., `us-central`, `asia-south1`)
4. Click **"Enable"**

### Step 2.3: Set Up Storage
1. Go to **"Storage"** → **"Get started"**
2. **Start in test mode** (similar rules as Firestore)
3. **Select same location** as Firestore
4. Click **"Done"**

---

## 💻 PHASE 3: Configure Flutter App (30 minutes)

### Step 3.1: Create Firebase Config File

**📁 Create file**: `lib/core/config/firebase_config.dart`

```dart
class FirebaseConfig {
  // 🔴 REPLACE THESE WITH YOUR ACTUAL FIREBASE VALUES FROM STEP 1.2
  
  // Web Configuration
  static const String webApiKey = "AIza...YOUR_API_KEY";
  static const String webAuthDomain = "your-project.firebaseapp.com";
  static const String webProjectId = "your-project-id";
  static const String webStorageBucket = "your-project.appspot.com";
  static const String webMessagingSenderId = "123456789";
  static const String webAppId = "1:123456789:web:abc123";
  
  // Android Configuration (add when you create Android app)
  static const String androidApiKey = "AIza...YOUR_ANDROID_API_KEY";
  static const String androidAppId = "1:123456789:android:xyz789";
  
  // iOS Configuration (add when you create iOS app)
  static const String iosApiKey = "AIza...YOUR_IOS_API_KEY";
  static const String iosAppId = "1:123456789:ios:def456";
  static const String iosClientId = "123456789-xxx.apps.googleusercontent.com";
  static const String iosBundleId = "com.lenv.newReward";
}
```

### Step 3.2: Update main.dart with Firebase Initialization

**📁 File**: `lib/main.dart`

```dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'core/config/firebase_config.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/role_provider.dart';
import 'providers/test_provider.dart';
import 'providers/reward_provider.dart';
import 'providers/teacher_dashboard_provider.dart';  // NEW
import 'routes/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: FirebaseConfig.webApiKey,
      authDomain: FirebaseConfig.webAuthDomain,
      projectId: FirebaseConfig.webProjectId,
      storageBucket: FirebaseConfig.webStorageBucket,
      messagingSenderId: FirebaseConfig.webMessagingSenderId,
      appId: FirebaseConfig.webAppId,
    ),
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => RoleProvider()),
        ChangeNotifierProvider(create: (_) => TestProvider()),
        ChangeNotifierProvider(create: (_) => RewardProvider()),
        ChangeNotifierProvider(create: (_) => TeacherDashboardProvider()),  // NEW
      ],
      child: MaterialApp(
        title: 'LenV - Educational Ecosystem',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        onGenerateRoute: AppRouter.generateRoute,
        initialRoute: '/',
      ),
    );
  }
}
```

### Step 3.3: Add Firebase Options File (Alternative Method)

**📁 Create file**: `lib/firebase_options.dart`

```dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'core/config/firebase_config.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: FirebaseConfig.webApiKey,
    authDomain: FirebaseConfig.webAuthDomain,
    projectId: FirebaseConfig.webProjectId,
    storageBucket: FirebaseConfig.webStorageBucket,
    messagingSenderId: FirebaseConfig.webMessagingSenderId,
    appId: FirebaseConfig.webAppId,
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: FirebaseConfig.androidApiKey,
    appId: FirebaseConfig.androidAppId,
    messagingSenderId: FirebaseConfig.webMessagingSenderId,
    projectId: FirebaseConfig.webProjectId,
    storageBucket: FirebaseConfig.webStorageBucket,
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: FirebaseConfig.iosApiKey,
    appId: FirebaseConfig.iosAppId,
    messagingSenderId: FirebaseConfig.webMessagingSenderId,
    projectId: FirebaseConfig.webProjectId,
    storageBucket: FirebaseConfig.webStorageBucket,
    iosBundleId: FirebaseConfig.iosBundleId,
    iosClientId: FirebaseConfig.iosClientId,
  );
}
```

---

## 🗄️ PHASE 4: Create Firestore Data Models (45 minutes)

### Step 4.1: Teacher Model

**📁 Create file**: `lib/models/teacher_model.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class TeacherModel {
  final String id;
  final String name;
  final String email;
  final String? profileImage;
  final String? phone;
  final String department;
  final String qualification;
  final int experienceYears;
  final String designation;
  final String instituteId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  TeacherModel({
    required this.id,
    required this.name,
    required this.email,
    this.profileImage,
    this.phone,
    required this.department,
    required this.qualification,
    required this.experienceYears,
    required this.designation,
    required this.instituteId,
    required this.createdAt,
    this.updatedAt,
  });

  factory TeacherModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TeacherModel(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      profileImage: data['profileImage'],
      phone: data['phone'],
      department: data['department'] ?? '',
      qualification: data['qualification'] ?? '',
      experienceYears: data['experienceYears'] ?? 0,
      designation: data['designation'] ?? '',
      instituteId: data['instituteId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'profileImage': profileImage,
      'phone': phone,
      'department': department,
      'qualification': qualification,
      'experienceYears': experienceYears,
      'designation': designation,
      'instituteId': instituteId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }
}
```

### Step 4.2: Class Model

**📁 Create file**: `lib/models/class_model.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ClassModel {
  final String id;
  final String className;
  final String subject;
  final String teacherId;
  final int studentCount;
  final String standard;
  final String section;
  final String? imageUrl;
  final DateTime createdAt;

  ClassModel({
    required this.id,
    required this.className,
    required this.subject,
    required this.teacherId,
    required this.studentCount,
    required this.standard,
    required this.section,
    this.imageUrl,
    required this.createdAt,
  });

  factory ClassModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ClassModel(
      id: doc.id,
      className: data['className'] ?? '',
      subject: data['subject'] ?? '',
      teacherId: data['teacherId'] ?? '',
      studentCount: data['studentCount'] ?? 0,
      standard: data['standard'] ?? '',
      section: data['section'] ?? '',
      imageUrl: data['imageUrl'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'className': className,
      'subject': subject,
      'teacherId': teacherId,
      'studentCount': studentCount,
      'standard': standard,
      'section': section,
      'imageUrl': imageUrl,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
```

### Step 4.3: Dashboard Stats Model

**📁 Create file**: `lib/models/dashboard_stats_model.dart`

```dart
class DashboardStats {
  final int totalClasses;
  final int totalStudents;
  final int liveTests;
  final double averagePerformance;
  final int totalTests;
  final int scheduledTests;
  final int newStudentsThisMonth;
  final int testsThisMonth;

  DashboardStats({
    required this.totalClasses,
    required this.totalStudents,
    required this.liveTests,
    required this.averagePerformance,
    required this.totalTests,
    required this.scheduledTests,
    required this.newStudentsThisMonth,
    required this.testsThisMonth,
  });

  factory DashboardStats.initial() {
    return DashboardStats(
      totalClasses: 0,
      totalStudents: 0,
      liveTests: 0,
      averagePerformance: 0.0,
      totalTests: 0,
      scheduledTests: 0,
      newStudentsThisMonth: 0,
      testsThisMonth: 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalClasses': totalClasses,
      'totalStudents': totalStudents,
      'liveTests': liveTests,
      'averagePerformance': averagePerformance,
      'totalTests': totalTests,
      'scheduledTests': scheduledTests,
      'newStudentsThisMonth': newStudentsThisMonth,
      'testsThisMonth': testsThisMonth,
    };
  }
}
```

### Step 4.4: Alert Model

**📁 Create file**: `lib/models/alert_model.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum AlertType { info, warning, urgent, success }

class AlertModel {
  final String id;
  final String title;
  final String message;
  final AlertType type;
  final String? relatedId; // testId, classId, studentId
  final DateTime createdAt;
  final bool isRead;

  AlertModel({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.relatedId,
    required this.createdAt,
    this.isRead = false,
  });

  factory AlertModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AlertModel(
      id: doc.id,
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      type: AlertType.values.firstWhere(
        (e) => e.toString() == 'AlertType.${data['type']}',
        orElse: () => AlertType.info,
      ),
      relatedId: data['relatedId'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isRead: data['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'message': message,
      'type': type.toString().split('.').last,
      'relatedId': relatedId,
      'createdAt': Timestamp.fromDate(createdAt),
      'isRead': isRead,
    };
  }
}
```

### Step 4.5: Recent Activity Model

**📁 Create file**: `lib/models/activity_model.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum ActivityType {
  testCreated,
  testCompleted,
  studentAdded,
  classCreated,
  gradeSubmitted,
  other
}

class ActivityModel {
  final String id;
  final String title;
  final String description;
  final ActivityType type;
  final DateTime timestamp;
  final String? relatedId;
  final String? relatedName;

  ActivityModel({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.timestamp,
    this.relatedId,
    this.relatedName,
  });

  factory ActivityModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ActivityModel(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      type: ActivityType.values.firstWhere(
        (e) => e.toString() == 'ActivityType.${data['type']}',
        orElse: () => ActivityType.other,
      ),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      relatedId: data['relatedId'],
      relatedName: data['relatedName'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'type': type.toString().split('.').last,
      'timestamp': Timestamp.fromDate(timestamp),
      'relatedId': relatedId,
      'relatedName': relatedName,
    };
  }
}
```

---

## 🔌 PHASE 5: Create Firebase Services (60 minutes)

### Step 5.1: Teacher Dashboard Service

**📁 Create file**: `lib/services/teacher_dashboard_service.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/dashboard_stats_model.dart';
import '../models/class_model.dart';
import '../models/alert_model.dart';
import '../models/activity_model.dart';

class TeacherDashboardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get Dashboard Statistics
  Future<DashboardStats> getDashboardStats(String teacherId) async {
    try {
      // Get total classes
      final classesSnapshot = await _firestore
          .collection('classes')
          .where('teacherId', isEqualTo: teacherId)
          .get();
      final totalClasses = classesSnapshot.docs.length;

      // Calculate total students across all classes
      int totalStudents = 0;
      for (var classDoc in classesSnapshot.docs) {
        totalStudents += (classDoc.data()['studentCount'] ?? 0) as int;
      }

      // Get tests statistics
      final testsSnapshot = await _firestore
          .collection('tests')
          .where('teacherId', isEqualTo: teacherId)
          .get();

      int liveTests = 0;
      int scheduledTests = 0;
      int totalTests = testsSnapshot.docs.length;

      for (var testDoc in testsSnapshot.docs) {
        final status = testDoc.data()['status'] ?? '';
        if (status == 'live') liveTests++;
        if (status == 'scheduled') scheduledTests++;
      }

      // Get this month's data
      final now = DateTime.now();
      final firstDayOfMonth = DateTime(now.year, now.month, 1);

      final newStudentsSnapshot = await _firestore
          .collection('students')
          .where('createdAt', isGreaterThanOrEqualTo: firstDayOfMonth)
          .get();

      final testsThisMonthSnapshot = await _firestore
          .collection('tests')
          .where('teacherId', isEqualTo: teacherId)
          .where('createdAt', isGreaterThanOrEqualTo: firstDayOfMonth)
          .get();

      // Calculate average performance (from completed tests)
      final completedTestsSnapshot = await _firestore
          .collection('tests')
          .where('teacherId', isEqualTo: teacherId)
          .where('status', isEqualTo: 'completed')
          .get();

      double totalPerformance = 0;
      int performanceCount = 0;

      for (var testDoc in completedTestsSnapshot.docs) {
        final avgScore = testDoc.data()['averageScore'];
        if (avgScore != null) {
          totalPerformance += (avgScore as num).toDouble();
          performanceCount++;
        }
      }

      final averagePerformance = performanceCount > 0
          ? totalPerformance / performanceCount
          : 0.0;

      return DashboardStats(
        totalClasses: totalClasses,
        totalStudents: totalStudents,
        liveTests: liveTests,
        averagePerformance: averagePerformance,
        totalTests: totalTests,
        scheduledTests: scheduledTests,
        newStudentsThisMonth: newStudentsSnapshot.docs.length,
        testsThisMonth: testsThisMonthSnapshot.docs.length,
      );
    } catch (e) {
      print('Error getting dashboard stats: $e');
      return DashboardStats.initial();
    }
  }

  // Get Teacher's Classes (limited to 6 for dashboard)
  Future<List<ClassModel>> getTeacherClasses(String teacherId, {int limit = 6}) async {
    try {
      final snapshot = await _firestore
          .collection('classes')
          .where('teacherId', isEqualTo: teacherId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => ClassModel.fromFirestore(doc)).toList();
    } catch (e) {
      print('Error getting teacher classes: $e');
      return [];
    }
  }

  // Get Recent Alerts
  Future<List<AlertModel>> getRecentAlerts(String teacherId, {int limit = 5}) async {
    try {
      final snapshot = await _firestore
          .collection('alerts')
          .where('teacherId', isEqualTo: teacherId)
          .where('isRead', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => AlertModel.fromFirestore(doc)).toList();
    } catch (e) {
      print('Error getting alerts: $e');
      return [];
    }
  }

  // Get Recent Activities
  Future<List<ActivityModel>> getRecentActivities(String teacherId, {int limit = 10}) async {
    try {
      final snapshot = await _firestore
          .collection('activities')
          .where('teacherId', isEqualTo: teacherId)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => ActivityModel.fromFirestore(doc)).toList();
    } catch (e) {
      print('Error getting activities: $e');
      return [];
    }
  }

  // Mark Alert as Read
  Future<void> markAlertAsRead(String alertId) async {
    try {
      await _firestore
          .collection('alerts')
          .doc(alertId)
          .update({'isRead': true});
    } catch (e) {
      print('Error marking alert as read: $e');
    }
  }

  // Listen to real-time dashboard updates
  Stream<DashboardStats> dashboardStatsStream(String teacherId) {
    // Return a stream that updates every time relevant data changes
    return Stream.periodic(const Duration(seconds: 30), (_) async {
      return await getDashboardStats(teacherId);
    }).asyncMap((event) => event);
  }
}
```

---

## 📦 PHASE 6: Create Provider for Dashboard (30 minutes)

### Step 6.1: Teacher Dashboard Provider

**📁 Create file**: `lib/providers/teacher_dashboard_provider.dart`

```dart
import 'package:flutter/foundation.dart';
import '../models/dashboard_stats_model.dart';
import '../models/class_model.dart';
import '../models/alert_model.dart';
import '../models/activity_model.dart';
import '../services/teacher_dashboard_service.dart';

class TeacherDashboardProvider with ChangeNotifier {
  final TeacherDashboardService _dashboardService = TeacherDashboardService();

  // State variables
  DashboardStats _stats = DashboardStats.initial();
  List<ClassModel> _classes = [];
  List<AlertModel> _alerts = [];
  List<ActivityModel> _activities = [];
  
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  DashboardStats get stats => _stats;
  List<ClassModel> get classes => _classes;
  List<AlertModel> get alerts => _alerts;
  List<ActivityModel> get activities => _activities;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Load all dashboard data
  Future<void> loadDashboardData(String teacherId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Load all data in parallel
      final results = await Future.wait([
        _dashboardService.getDashboardStats(teacherId),
        _dashboardService.getTeacherClasses(teacherId, limit: 6),
        _dashboardService.getRecentAlerts(teacherId, limit: 5),
        _dashboardService.getRecentActivities(teacherId, limit: 10),
      ]);

      _stats = results[0] as DashboardStats;
      _classes = results[1] as List<ClassModel>;
      _alerts = results[2] as List<AlertModel>;
      _activities = results[3] as List<ActivityModel>;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load dashboard data: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // Refresh dashboard data
  Future<void> refreshDashboard(String teacherId) async {
    await loadDashboardData(teacherId);
  }

  // Mark alert as read
  Future<void> markAlertAsRead(String alertId) async {
    try {
      await _dashboardService.markAlertAsRead(alertId);
      _alerts = _alerts.map((alert) {
        if (alert.id == alertId) {
          return AlertModel(
            id: alert.id,
            title: alert.title,
            message: alert.message,
            type: alert.type,
            createdAt: alert.createdAt,
            isRead: true,
            relatedId: alert.relatedId,
          );
        }
        return alert;
      }).toList();
      notifyListeners();
    } catch (e) {
      print('Error marking alert as read: $e');
    }
  }

  // Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
```

---

## 🎨 PHASE 7: Update Teacher Dashboard Screen (45 minutes)

### Step 7.1: Make Dashboard Dynamic

**Update**: `lib/screens/teacher/teacher_dashboard_screen.dart`

Key changes:
1. Add Provider dependency
2. Load data in `initState`
3. Replace static data with Provider data
4. Add pull-to-refresh
5. Show loading states

```dart
// Add at top of file
import 'package:provider/provider.dart';
import '../../providers/teacher_dashboard_provider.dart';
import '../../providers/auth_provider.dart';

// In initState
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final teacherId = authProvider.currentUser?.id ?? 'temp_teacher_id';
    
    Provider.of<TeacherDashboardProvider>(context, listen: false)
        .loadDashboardData(teacherId);
  });
}

// Wrap body with Consumer
body: Consumer<TeacherDashboardProvider>(
  builder: (context, dashboardProvider, child) {
    if (dashboardProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return RefreshIndicator(
      onRefresh: () async {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final teacherId = authProvider.currentUser?.id ?? 'temp_teacher_id';
        await dashboardProvider.refreshDashboard(teacherId);
      },
      child: SingleChildScrollView(
        // ... existing UI
      ),
    );
  },
),
```

---

## 🗃️ PHASE 8: Firestore Database Structure (15 minutes)

### Firestore Collections Structure:

```
firestore/
├── users/
│   └── {userId}
│       ├── email: string
│       ├── name: string
│       ├── role: string ('teacher', 'student', 'parent', 'institute')
│       ├── profileImage: string (URL)
│       ├── createdAt: timestamp
│       └── instituteId: string
│
├── teachers/
│   └── {teacherId} (same as userId)
│       ├── name: string
│       ├── email: string
│       ├── phone: string
│       ├── department: string
│       ├── qualification: string
│       ├── experienceYears: number
│       ├── designation: string
│       ├── profileImage: string (URL)
│       ├── instituteId: string
│       ├── createdAt: timestamp
│       └── updatedAt: timestamp
│
├── classes/
│   └── {classId}
│       ├── className: string
│       ├── subject: string
│       ├── teacherId: string (ref to teachers)
│       ├── studentCount: number
│       ├── standard: string ('10', '11', '12')
│       ├── section: string ('A', 'B', 'C')
│       ├── imageUrl: string
│       └── createdAt: timestamp
│
├── students/
│   └── {studentId}
│       ├── name: string
│       ├── email: string
│       ├── classId: string (ref to classes)
│       ├── standard: string
│       ├── section: string
│       ├── profileImage: string
│       ├── parentId: string (ref to users)
│       └── createdAt: timestamp
│
├── tests/
│   └── {testId}
│       ├── testName: string
│       ├── teacherId: string (ref to teachers)
│       ├── classId: string (ref to classes)
│       ├── subject: string
│       ├── duration: number (minutes)
│       ├── totalMarks: number
│       ├── questions: array
│       ├── status: string ('scheduled', 'live', 'completed')
│       ├── scheduledAt: timestamp
│       ├── startedAt: timestamp
│       ├── endedAt: timestamp
│       ├── averageScore: number
│       └── createdAt: timestamp
│
├── test_results/
│   └── {resultId}
│       ├── testId: string (ref to tests)
│       ├── studentId: string (ref to students)
│       ├── score: number
│       ├── totalMarks: number
│       ├── percentage: number
│       ├── answers: array
│       ├── timeTaken: number (seconds)
│       └── submittedAt: timestamp
│
├── alerts/
│   └── {alertId}
│       ├── teacherId: string (ref to teachers)
│       ├── title: string
│       ├── message: string
│       ├── type: string ('info', 'warning', 'urgent', 'success')
│       ├── relatedId: string (testId/classId/studentId)
│       ├── isRead: boolean
│       └── createdAt: timestamp
│
└── activities/
    └── {activityId}
        ├── teacherId: string (ref to teachers)
        ├── title: string
        ├── description: string
        ├── type: string ('testCreated', 'testCompleted', etc.)
        ├── relatedId: string
        ├── relatedName: string
        └── timestamp: timestamp
```

---

## 🧪 PHASE 9: Add Sample Data to Firestore (30 minutes)

### Step 9.1: Create Data Seeding Script

**📁 Create file**: `lib/utils/seed_data.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/class_model.dart';
import '../models/alert_model.dart';
import '../models/activity_model.dart';

class SeedData {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Seed sample data for testing
  static Future<void> seedTeacherData(String teacherId) async {
    try {
      // Add teacher document
      await _firestore.collection('teachers').doc(teacherId).set({
        'name': 'Dr. Jane Doe',
        'email': 'jane.doe@learnq.edu',
        'phone': '+1 234 567 8900',
        'department': 'Computer Science',
        'qualification': 'Ph.D. in AI',
        'experienceYears': 15,
        'designation': 'Senior Professor',
        'profileImage': 'https://lh3.googleusercontent.com/...',
        'instituteId': 'inst_001',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Add sample classes
      final classesData = [
        {
          'className': 'Grade 10 - Mathematics',
          'subject': 'Mathematics',
          'teacherId': teacherId,
          'studentCount': 35,
          'standard': '10',
          'section': 'A',
          'imageUrl': 'https://images.unsplash.com/photo-1596495577886-d920f1fb7238',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'className': 'Grade 11 - Physics',
          'subject': 'Physics',
          'teacherId': teacherId,
          'studentCount': 28,
          'standard': '11',
          'section': 'B',
          'imageUrl': 'https://images.unsplash.com/photo-1636466497217-26a8cbeaf0aa',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'className': 'Grade 12 - Chemistry',
          'subject': 'Chemistry',
          'teacherId': teacherId,
          'studentCount': 30,
          'standard': '12',
          'section': 'A',
          'imageUrl': 'https://images.unsplash.com/photo-1532094349884-543bc11b234d',
          'createdAt': FieldValue.serverTimestamp(),
        },
      ];

      for (var classData in classesData) {
        await _firestore.collection('classes').add(classData);
      }

      // Add sample alerts
      final alertsData = [
        {
          'teacherId': teacherId,
          'title': 'Test Submission Alert',
          'message': 'Physics Test - 5 students haven\'t submitted yet',
          'type': 'warning',
          'relatedId': 'test_001',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'teacherId': teacherId,
          'title': 'Low Performance Alert',
          'message': 'Chemistry Test - Class average below 60%',
          'type': 'urgent',
          'relatedId': 'test_002',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
      ];

      for (var alertData in alertsData) {
        await _firestore.collection('alerts').add(alertData);
      }

      // Add sample activities
      final activitiesData = [
        {
          'teacherId': teacherId,
          'title': 'Test Created',
          'description': 'Physics Mid-term Exam scheduled',
          'type': 'testCreated',
          'relatedId': 'test_003',
          'relatedName': 'Physics Mid-term',
          'timestamp': FieldValue.serverTimestamp(),
        },
        {
          'teacherId': teacherId,
          'title': 'Test Completed',
          'description': 'Math Quiz completed by all students',
          'type': 'testCompleted',
          'relatedId': 'test_004',
          'relatedName': 'Math Quiz',
          'timestamp': FieldValue.serverTimestamp(),
        },
      ];

      for (var activityData in activitiesData) {
        await _firestore.collection('activities').add(activityData);
      }

      // Add sample tests
      await _firestore.collection('tests').add({
        'testName': 'Physics Mid-term Exam',
        'teacherId': teacherId,
        'classId': 'class_001',
        'subject': 'Physics',
        'duration': 60,
        'totalMarks': 100,
        'status': 'live',
        'averageScore': 82.5,
        'scheduledAt': Timestamp.now(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('tests').add({
        'testName': 'Chemistry Quiz',
        'teacherId': teacherId,
        'classId': 'class_002',
        'subject': 'Chemistry',
        'duration': 30,
        'totalMarks': 50,
        'status': 'scheduled',
        'scheduledAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 2)),
        ),
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('✅ Sample data seeded successfully!');
    } catch (e) {
      print('❌ Error seeding data: $e');
    }
  }
}
```

---

## ✅ PHASE 10: Testing & Verification (30 minutes)

### Checklist:

- [ ] **Firebase Console Access**: Can you log in to Firebase Console?
- [ ] **App Runs**: Does `flutter run -d chrome` work without errors?
- [ ] **Firebase Initialized**: Check browser console for "Firebase initialized"
- [ ] **Data Loads**: Dashboard shows loading indicator, then data
- [ ] **Pull to Refresh**: Swipe down on dashboard refreshes data
- [ ] **Firestore Data**: View data in Firebase Console → Firestore Database
- [ ] **Real-time Updates**: Change data in Firestore, see it reflect in app
- [ ] **Error Handling**: Disconnect internet, see error message

---

## 📝 Complete To-Do List Summary

### ✅ **Part 1: Firebase Setup (1-2 hours)**
1. [ ] Create Firebase project at console.firebase.google.com
2. [ ] Register Web app and copy Firebase config values
3. [ ] Enable Email/Password authentication
4. [ ] Create Firestore database (test mode)
5. [ ] Set up Firebase Storage (test mode)
6. [ ] Create `firebase_config.dart` with your API keys
7. [ ] Create `firebase_options.dart` for platform-specific config
8. [ ] Update `main.dart` to initialize Firebase

### ✅ **Part 2: Data Models (1 hour)**
9. [ ] Create `teacher_model.dart`
10. [ ] Create `class_model.dart`
11. [ ] Create `dashboard_stats_model.dart`
12. [ ] Create `alert_model.dart`
13. [ ] Create `activity_model.dart`

### ✅ **Part 3: Services & Providers (1.5 hours)**
14. [ ] Create `teacher_dashboard_service.dart`
15. [ ] Create `teacher_dashboard_provider.dart`
16. [ ] Register provider in `main.dart`

### ✅ **Part 4: Update UI (1 hour)**
17. [ ] Update `teacher_dashboard_screen.dart` to use Provider
18. [ ] Add loading states and error handling
19. [ ] Implement pull-to-refresh
20. [ ] Connect all widgets to dynamic data

### ✅ **Part 5: Seed Data & Test (1 hour)**
21. [ ] Create `seed_data.dart` utility
22. [ ] Run seed data script (call from a test button)
23. [ ] Verify data in Firebase Console
24. [ ] Test dashboard with real data
25. [ ] Test all interactions (alerts, activities, class cards)

---

## 🚀 Quick Start Commands

```bash
# 1. Install/Update dependencies
flutter pub get

# 2. Run the app
flutter run -d chrome

# 3. If you get Firebase errors, check:
flutter doctor
flutter clean
flutter pub get
flutter run -d chrome
```

---

## 🔑 Where to Add Firebase Credentials

### Your Firebase Config (from Step 1.2):
```
📍 Location: lib/core/config/firebase_config.dart

Replace these values:
- webApiKey = "AIza..." (from Firebase Console)
- webAuthDomain = "your-project.firebaseapp.com"
- webProjectId = "your-project-id"
- webStorageBucket = "your-project.appspot.com"
- webMessagingSenderId = "123456789"
- webAppId = "1:123456789:web:abc123"
```

---

## 🎯 Expected Result After Implementation

✅ Teacher Dashboard will:
- Show **real-time** statistics from Firestore
- Display **actual classes** from database
- Show **live alerts** for pending actions
- Display **recent activities** chronologically
- Support **pull-to-refresh** for latest data
- Handle **loading states** and **errors** gracefully
- Work **offline** with cached data

---

## 🆘 Troubleshooting

### Error: "Firebase not initialized"
→ Check `main.dart` has `await Firebase.initializeApp()`

### Error: "Missing API key"
→ Verify `firebase_config.dart` has correct values from Firebase Console

### Error: "Permission denied" in Firestore
→ Check Firestore Rules are in test mode (allow read, write)

### Data not showing
→ Run `seed_data.dart` to add sample data
→ Check Firebase Console → Firestore to verify data exists

---

## 📞 Next Steps After This Implementation

1. **Implement Authentication Flow** (Login/Register screens)
2. **Make other screens dynamic** (Classes, Tests, Students, Leaderboard)
3. **Add real-time listeners** for live test updates
4. **Implement test creation** with Firestore
5. **Add image upload** to Firebase Storage
6. **Set up proper Firestore Security Rules**
7. **Add offline support** with local caching
8. **Implement push notifications** for alerts

---

**Total Estimated Time: 6-8 hours**

**Difficulty: Intermediate**

**Prerequisites: Firebase account, Basic Dart/Flutter knowledge**

---

Good luck! 🎉 Start with Phase 1 and work your way through. Each phase builds on the previous one.
