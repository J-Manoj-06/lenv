import 'package:flutter/material.dart' hide Badge;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/badge_service.dart';
import '../widgets/badge_card.dart';
import '../badges/badge_model.dart';

class AchievementSection extends StatefulWidget {
  final String studentId;
  const AchievementSection({super.key, required this.studentId});

  @override
  State<AchievementSection> createState() => _AchievementSectionState();
}

class _AchievementSectionState extends State<AchievementSection> {
  final _service = BadgeService();
  String? _currentStudentId;

  @override
  void didUpdateWidget(covariant AchievementSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId) {
      setState(() {
        _currentStudentId = widget.studentId;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _currentStudentId = widget.studentId;
  }

  Stream<List<Badge>> _badgeStream(String studentId) async* {
    final firestore = FirebaseFirestore.instance;

    // Merge two sources: student_badges doc and students doc fallback
    yield* firestore
        .collection('student_badges')
        .doc(studentId)
        .snapshots()
        .asyncMap((snap) async {
          List<dynamic> raw = (snap.data()?['badges'] ?? []) as List<dynamic>;
          if (raw.isEmpty) {
            // Try fallback students doc
            final sdoc = await firestore
                .collection('students')
                .doc(studentId)
                .get();
            raw = (sdoc.data()?['badges'] ?? []) as List<dynamic>;
          }
          final mapped = <Badge>[];
          for (final r in raw) {
            if (r is Map<String, dynamic>) {
              final id = r['id'] as String?;
              if (id == null) continue;
              final all = await _service.fetchEarnedBadges(
                studentId,
              ); // reuse mapping logic
              // fetchEarnedBadges already maps all; but we only need to map once
              return all; // short-circuit
            }
          }
          // If raw empty
          return mapped;
        });
  }

  @override
  Widget build(BuildContext context) {
    final sid = _currentStudentId;
    if (sid == null || sid.isEmpty) {
      return const SizedBox(height: 120);
    }
    return StreamBuilder<List<Badge>>(
      stream: _badgeStream(sid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return SizedBox(
            height: 120,
            child: Center(
              child: Text(
                'Unable to load achievements',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }
        final badges = snapshot.data ?? const <Badge>[];
        if (badges.isEmpty) {
          return SizedBox(
            height: 120,
            child: Center(
              child: Text(
                'No Achievements Yet',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }
        return SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) => BadgeCard(badge: badges[index]),
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemCount: badges.length,
          ),
        );
      },
    );
  }
}
