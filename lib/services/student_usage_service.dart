import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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

  const StudentDailyUsage({
    required this.studentId,
    required this.date,
    required this.permissionEnabled,
    required this.topApps,
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

  Future<void> collectAndSyncTodayUsage({required String studentId}) async {
    if (!Platform.isAndroid || studentId.trim().isEmpty) return;

    final date = _todayDateKey();
    final docId = '${studentId}_$date';

    final permissionGranted = await isUsagePermissionGranted();

    List<AppUsageItem> topApps = const [];
    if (permissionGranted) {
      try {
        topApps = await _fetchTopAppsTodayFromDevice();
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
          'topApps': topApps.map((e) => e.toMap()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: false));

    _sessionCache['${studentId}_$date'] = StudentDailyUsage(
      studentId: studentId,
      date: date,
      permissionEnabled: permissionGranted,
      topApps: topApps,
    );
  }

  Future<StudentDailyUsage?> getTodayUsageForStudent({
    required String studentId,
    bool forceRefresh = false,
  }) async {
    if (studentId.trim().isEmpty) return null;

    final date = _todayDateKey();
    final cacheKey = '${studentId}_$date';

    if (!forceRefresh && _sessionCache.containsKey(cacheKey)) {
      return _sessionCache[cacheKey];
    }

    final docId = '${studentId}_$date';
    final doc = await FirebaseFirestore.instance
        .collection('student_app_usage')
        .doc(docId)
        .get();

    if (!doc.exists) {
      _sessionCache[cacheKey] = null;
      return null;
    }

    final parsed = StudentDailyUsage.fromDoc(doc);
    _sessionCache[cacheKey] = parsed;
    return parsed;
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
