import 'package:cloud_firestore/cloud_firestore.dart';

import 'student_usage_service.dart';

enum UsagePriority { high, medium, low, unknown }

class TeacherStudentUsageSummary {
  final String studentId;
  final bool? permissionEnabled;
  final List<AppUsageItem> topApps;
  final int socialUsageMinutes;
  final int totalUsageMinutes;
  final UsagePriority priority;

  const TeacherStudentUsageSummary({
    required this.studentId,
    required this.permissionEnabled,
    required this.topApps,
    required this.socialUsageMinutes,
    required this.totalUsageMinutes,
    required this.priority,
  });

  bool get hasData => permissionEnabled != null;
}

class AppUsageService {
  static const Set<String> _socialMediaPackages = {
    'com.instagram.android',
    'com.whatsapp',
    'com.facebook.katana',
    'com.snapchat.android',
    'com.google.android.youtube',
  };

  static final Map<String, Map<String, TeacherStudentUsageSummary>>
  _sessionCache = {};

  static String _todayDateKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  static UsagePriority _priorityFromSocialMinutes(int minutes) {
    if (minutes >= 120) return UsagePriority.high;
    if (minutes >= 60) return UsagePriority.medium;
    return UsagePriority.low;
  }

  Future<Map<String, TeacherStudentUsageSummary>> getClassTodayUsage({
    required String classId,
    required List<String> studentIds,
    bool forceRefresh = false,
  }) async {
    final date = _todayDateKey();
    final ids = studentIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) return {};

    final cacheKey = '$classId|$date';
    final cached = _sessionCache[cacheKey];
    if (!forceRefresh && cached != null && ids.every(cached.containsKey)) {
      return {for (final id in ids) id: cached[id]!};
    }

    final docIds = ids.map((id) => '${id}_$date').toList();
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    const chunkSize = 10;
    for (int i = 0; i < docIds.length; i += chunkSize) {
      final end = (i + chunkSize < docIds.length)
          ? i + chunkSize
          : docIds.length;
      final chunk = docIds.sublist(i, end);
      final snap = await FirebaseFirestore.instance
          .collection('student_app_usage')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      docs.addAll(snap.docs);
    }

    final result = <String, TeacherStudentUsageSummary>{};

    for (final studentId in ids) {
      result[studentId] = TeacherStudentUsageSummary(
        studentId: studentId,
        permissionEnabled: null,
        topApps: const [],
        socialUsageMinutes: 0,
        totalUsageMinutes: 0,
        priority: UsagePriority.unknown,
      );
    }

    for (final doc in docs) {
      final data = doc.data();
      final studentId = (data['studentId'] ?? '').toString().trim().isNotEmpty
          ? (data['studentId'] ?? '').toString().trim()
          : doc.id.split('_').first;
      if (!result.containsKey(studentId)) continue;

      final permissionEnabled = data['permissionEnabled'] as bool?;
      final rawTopApps = (data['topApps'] as List?) ?? const [];
      final topApps =
          rawTopApps
              .whereType<Map>()
              .map((e) => AppUsageItem.fromMap(Map<String, dynamic>.from(e)))
              .where((e) => e.appName.isNotEmpty && e.packageName.isNotEmpty)
              .toList()
            ..sort((a, b) => b.usageMinutes.compareTo(a.usageMinutes));

      final socialUsageMinutes = topApps
          .where((app) => _socialMediaPackages.contains(app.packageName))
          .fold<int>(0, (acc, app) => acc + app.usageMinutes);

      final totalUsageMinutes = topApps.fold<int>(
        0,
        (acc, app) => acc + app.usageMinutes,
      );

      result[studentId] = TeacherStudentUsageSummary(
        studentId: studentId,
        permissionEnabled: permissionEnabled,
        topApps: topApps.take(5).toList(),
        socialUsageMinutes: socialUsageMinutes,
        totalUsageMinutes: totalUsageMinutes,
        priority: permissionEnabled == null
            ? UsagePriority.unknown
            : _priorityFromSocialMinutes(socialUsageMinutes),
      );
    }

    _sessionCache[cacheKey] = result;
    return result;
  }

  static String formatMinutes(int minutes) {
    if (minutes <= 0) return '0m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }
}
