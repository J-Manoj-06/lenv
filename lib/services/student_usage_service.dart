import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppUsageItem {
  final String appName;
  final String packageName;
  final int usageMinutes;
  final String? appIconBase64;

  const AppUsageItem({
    required this.appName,
    required this.packageName,
    required this.usageMinutes,
    this.appIconBase64,
  });

  factory AppUsageItem.fromMap(Map<String, dynamic> map) {
    return AppUsageItem(
      appName: (map['appName'] ?? '').toString(),
      packageName: (map['packageName'] ?? '').toString(),
      usageMinutes: (map['usageMinutes'] as num?)?.toInt() ?? 0,
      appIconBase64: map['appIcon']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'appName': appName,
      'packageName': packageName,
      'usageMinutes': usageMinutes,
      'appIcon': appIconBase64,
    };
  }
}

class StudentDailyUsage {
  final String studentId;
  final String date;
  final bool permissionEnabled;
  final List<AppUsageItem> topApps;
  final int? consideredAppCount;

  const StudentDailyUsage({
    required this.studentId,
    required this.date,
    required this.permissionEnabled,
    required this.topApps,
    this.consideredAppCount,
  });

  factory StudentDailyUsage.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawTopApps = (data['topApps'] as List?) ?? const [];

    final items = rawTopApps
        .whereType<Map>()
        .map((e) => AppUsageItem.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    return StudentDailyUsage(
      studentId: (data['studentId'] ?? '').toString(),
      date: (data['date'] ?? '').toString(),
      permissionEnabled: (data['permissionEnabled'] as bool?) ?? true,
      topApps: items,
      consideredAppCount: (data['consideredAppCount'] as num?)?.toInt(),
    );
  }
}

class StudentUsageService {
  static const MethodChannel _channel = MethodChannel('lenv/app_usage_tracker');
  static final Map<String, StudentDailyUsage?> _sessionCache = {};

  static String _todayDateKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  static String formatMinutes(int minutes) {
    if (minutes <= 0) return '0m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  Future<bool> isUsagePermissionGranted() async {
    if (!Platform.isAndroid) return false;

    try {
      final granted = await _channel.invokeMethod<bool>(
        'isUsagePermissionGranted',
      );
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openUsagePermissionSettings() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('openUsageAccessSettings');
    } catch (_) {
      // Non-blocking fallback; UI handles user guidance.
    }
  }

  Future<List<AppUsageItem>> _fetchTopAppsTodayFromDevice() async {
    if (!Platform.isAndroid) return const [];

    final raw = await _channel.invokeMethod<List<dynamic>>('getTopAppsToday', {
      'topN': 5,
    });

    if (raw == null) return const [];

    final items = raw
        .whereType<Map>()
        .map((e) => AppUsageItem.fromMap(Map<String, dynamic>.from(e)))
        .where((e) => e.appName.isNotEmpty && e.packageName.isNotEmpty)
        .toList();

    items.sort((a, b) => b.usageMinutes.compareTo(a.usageMinutes));
    return items.take(5).toList();
  }

  Future<int?> _fetchConsideredAppCount() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'getTopAppsToday',
        {'topN': 500},
      );
      return raw?.length;
    } catch (_) {
      return null;
    }
  }

  Future<void> collectAndSyncTodayUsage({required String studentId}) async {
    if (!Platform.isAndroid || studentId.trim().isEmpty) return;

    final date = _todayDateKey();
    final docId = '${studentId}_$date';

    final permissionGranted = await isUsagePermissionGranted();

    List<AppUsageItem> topApps = const [];
    int? consideredAppCount;
    if (permissionGranted) {
      try {
        topApps = await _fetchTopAppsTodayFromDevice();
        consideredAppCount = await _fetchConsideredAppCount();
      } on PlatformException {
        topApps = const [];
      }
    }

    await FirebaseFirestore.instance
        .collection('student_app_usage')
        .doc(docId)
        .set({
          'studentId': studentId,
          'date': date,
          'permissionEnabled': permissionGranted,
          'consideredAppCount': consideredAppCount,
          'topApps': topApps.map((e) => e.toMap()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: false));

    _sessionCache['${studentId}_$date'] = StudentDailyUsage(
      studentId: studentId,
      date: date,
      permissionEnabled: permissionGranted,
      topApps: topApps,
      consideredAppCount: consideredAppCount,
    );
  }

  Future<StudentDailyUsage?> getTodayUsageForStudent({
    required String studentId,
    bool forceRefresh = false,
  }) async {
    if (studentId.trim().isEmpty) return null;

    final date = _todayDateKey();
    final cacheKey = '${studentId}_$date';
    final authUser = FirebaseAuth.instance.currentUser;
    final docId = '${studentId}_$date';

    debugPrint(
      '📊 [AppUsage] getTodayUsageForStudent start '
      'studentId=$studentId docId=$docId forceRefresh=$forceRefresh '
      'authUid=${authUser?.uid} authEmail=${authUser?.email}',
    );

    if (!forceRefresh && _sessionCache.containsKey(cacheKey)) {
      debugPrint(
        '📊 [AppUsage] cache hit cacheKey=$cacheKey '
        'hasData=${_sessionCache[cacheKey] != null}',
      );
      return _sessionCache[cacheKey];
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('student_app_usage')
          .doc(docId)
          .get();

      if (!doc.exists) {
        debugPrint('📊 [AppUsage] doc missing docId=$docId');
        _sessionCache[cacheKey] = null;
        return null;
      }

      final parsed = StudentDailyUsage.fromDoc(doc);
      debugPrint(
        '📊 [AppUsage] doc loaded docId=$docId '
        'permissionEnabled=${parsed.permissionEnabled} '
        'topApps=${parsed.topApps.length} '
        'consideredAppCount=${parsed.consideredAppCount}',
      );
      _sessionCache[cacheKey] = parsed;
      return parsed;
    } on FirebaseException catch (e) {
      debugPrint(
        '❌ [AppUsage] firestore read failed '
        'collection=student_app_usage docId=$docId '
        'studentId=$studentId authUid=${authUser?.uid} '
        'code=${e.code} message=${e.message}',
      );
      rethrow;
    } catch (e) {
      debugPrint(
        '❌ [AppUsage] unexpected read error '
        'collection=student_app_usage docId=$docId '
        'studentId=$studentId authUid=${authUser?.uid} '
        'error=$e',
      );
      rethrow;
    }
  }

  Uint8List? decodeIcon(String? base64Icon) {
    if (base64Icon == null || base64Icon.trim().isEmpty) return null;
    try {
      return base64Decode(base64Icon);
    } catch (_) {
      return null;
    }
  }
}
