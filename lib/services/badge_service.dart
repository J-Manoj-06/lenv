import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:new_reward/badges/badge_master.dart';
import 'package:new_reward/badges/badge_model.dart';

class BadgeService {
  final _firestore = FirebaseFirestore.instance;

  Future<void> awardBadge(
    String studentId,
    String badgeId, {
    String? testId,
  }) async {
    // Prefer dedicated collection: student_badges/{studentId}
    final badgeDocRef = _firestore.collection('student_badges').doc(studentId);
    final badgeDoc = await badgeDocRef.get();
    final List<dynamic> existingBadges =
        (badgeDoc.data()?['badges'] ?? []) as List<dynamic>;

    // Check if this badge ID already exists
    final alreadyHas = existingBadges.any((b) => b['id'] == badgeId);
    if (alreadyHas) {
      print('⚠️ Badge $badgeId already awarded to student $studentId');
      return;
    }

    final entry = {
      'id': badgeId,
      'earnedOn': DateTime.now().millisecondsSinceEpoch,
      if (testId != null) 'testId': testId,
    };

    // Write to dedicated badges document (create if missing)
    if (!badgeDoc.exists) {
      await badgeDocRef.set({
        'badges': [entry],
      });
    } else {
      await badgeDocRef.update({
        'badges': FieldValue.arrayUnion([entry]),
      });
    }

    // Backward-compat: also update students/{id}.badges array if present
    try {
      await _firestore.collection('students').doc(studentId).update({
        'badges': FieldValue.arrayUnion([entry]),
      });
    } catch (_) {}

    print('✅ Awarded badge: $badgeId to student $studentId');
  }

  Future<List<Map<String, dynamic>>> fetchEarnedBadgesRaw(
    String studentId,
  ) async {
    // Read from dedicated collection first
    final badgeDoc = await _firestore
        .collection('student_badges')
        .doc(studentId)
        .get();
    List<dynamic> earned = (badgeDoc.data()?['badges'] ?? []) as List<dynamic>;

    // Fallback: students/{id}.badges array
    if (earned.isEmpty) {
      try {
        final sdoc = await _firestore
            .collection('students')
            .doc(studentId)
            .get();
        final sdata = sdoc.data();
        earned = (sdata?['badges'] ?? []) as List<dynamic>;
      } catch (_) {}
    }
    return earned.cast<Map<String, dynamic>>();
  }

  Future<List<Badge>> fetchEarnedBadges(String studentId) async {
    final earned = await fetchEarnedBadgesRaw(studentId);

    final List<Badge> result = [];
    for (final raw in earned) {
      final id = raw['id'] as String?;
      if (id == null) continue;
      final match = badgeMasterList.firstWhere(
        (b) => b.id == id,
        orElse: () => const Badge(
          id: 'unknown',
          title: 'Unknown Badge',
          description: 'Badge not found',
          emoji: '❓',
          category: 'other',
          points: 0,
        ),
      );
      result.add(match);
    }
    return result;
  }
}
