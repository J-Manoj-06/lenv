import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StudentMessagesScreen extends StatelessWidget {
  const StudentMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primary = Color(0xFFF27F0D); // student theme primary
    final bg = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8F7F5);
    final topbar = isDark ? const Color(0xFF141414) : const Color(0xFFF8F7F5);
    final card = isDark ? const Color(0xFF222222) : Colors.white;
    final textSecondary = isDark ? const Color(0xFFB0B0B0) : Colors.grey[600];

    return Scaffold(
      backgroundColor: bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AppBar(
          backgroundColor: topbar,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'Messages',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: const SizedBox(width: 48),
          actions: const [SizedBox(width: 48)],
        ),
      ),
      body: StreamBuilder<List<_SubjectEntry>>(
        stream: _subjectEntriesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mark_email_unread,
                      size: 64,
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No subjects assigned yet.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Your class groups will appear here.',
                      style: TextStyle(color: textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final icon = _iconForSubject(entry.subject);
              return InkWell(
                onTap: () {}, // conversation placeholder
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      if (isDark)
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                    ],
                    border: Border.all(
                      color: primary.withOpacity(0.15),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: primary, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.subject,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry.teacherName,
                              style: TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: textSecondary),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Stream<List<_SubjectEntry>> _subjectEntriesStream() async* {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      yield [];
      return;
    }
    // Listen to testResults for this student (real-time)
    final testResultsStream = FirebaseFirestore.instance
        .collection('testResults')
        .where('studentId', isEqualTo: uid)
        .snapshots();

    await for (final resultsSnap in testResultsStream) {
      final testIds = resultsSnap.docs
          .map((d) => d.data()['testId'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();
      if (testIds.isEmpty) {
        yield [];
        continue;
      }
      final List<_SubjectEntry> entries = [];
      // Batch fetch scheduledTests docs (whereIn limit 10)
      for (var i = 0; i < testIds.length; i += 10) {
        final batch = testIds.skip(i).take(10).toList();
        final testsSnap = await FirebaseFirestore.instance
            .collection('scheduledTests')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in testsSnap.docs) {
          final data = doc.data();
          final subject = (data['subject'] as String?)?.trim() ?? '';
          final teacherName =
              (data['teacherName'] as String?)?.trim() ?? 'Teacher';
          if (subject.isEmpty) continue;
          // Use combination subject+teacherName for uniqueness
          if (!entries.any(
            (e) => e.subject == subject && e.teacherName == teacherName,
          )) {
            entries.add(
              _SubjectEntry(subject: subject, teacherName: teacherName),
            );
          }
        }
      }
      // Sort alphabetically by subject
      entries.sort(
        (a, b) => a.subject.toLowerCase().compareTo(b.subject.toLowerCase()),
      );
      yield entries;
    }
  }

  IconData _iconForSubject(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('math')) return Icons.calculate;
    if (s.contains('science')) return Icons.science;
    if (s.contains('social')) return Icons.public;
    if (s.contains('english')) return Icons.translate;
    if (s.contains('chem')) return Icons.biotech;
    if (s.contains('phy')) return Icons.bolt;
    return Icons.menu_book;
  }
}

class _SubjectEntry {
  final String subject;
  final String teacherName;
  _SubjectEntry({required this.subject, required this.teacherName});
}

// Removed unused _SubjectItem placeholder after wiring real-time Firestore data.
