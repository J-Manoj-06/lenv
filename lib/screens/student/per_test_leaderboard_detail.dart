import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class PerTestLeaderboardDetail extends StatefulWidget {
  final String testId;
  final String testTitle;
  final String subject;

  const PerTestLeaderboardDetail({
    super.key,
    required this.testId,
    required this.testTitle,
    required this.subject,
  });

  @override
  State<PerTestLeaderboardDetail> createState() =>
      _PerTestLeaderboardDetailState();
}

class _PerTestLeaderboardDetailState extends State<PerTestLeaderboardDetail> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentStudentId = authProvider.currentUser?.uid;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111111) : Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_ios_new,
                          color: isDark ? Colors.white : Colors.black87,
                          size: 24,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          'Leaderboard',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1D21),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 40), // Balance for back button
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.testTitle}${widget.subject.isNotEmpty ? ' - ${widget.subject}' : ''}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? const Color(0xFFA1A1AA) : Colors.black54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // Leaderboard Content
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('testResults')
                    .where('testId', isEqualTo: widget.testId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF7B00),
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1A1A1A)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(48),
                            ),
                            child: Icon(
                              Icons.menu_book,
                              size: 48,
                              color: isDark
                                  ? const Color(0xFF52525B)
                                  : Colors.black26,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No students assigned yet',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1D21),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Students will appear once test is assigned',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF71717A)
                                  : Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Parse results and deduplicate by studentId (keep highest score)
                  final Map<String, Map<String, Object?>> bestByStudent = {};

                  for (final doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final studentId = data['studentId'] as String? ?? '';

                    if (studentId.isEmpty) continue;

                    final score = (data['score'] as num?)?.toDouble() ?? 0.0;
                    final studentName =
                        data['studentName'] as String? ?? 'Unknown';
                    final className = data['className'] as String? ?? '';
                    final section = data['section'] as String? ?? '';

                    final result = <String, Object?>{
                      'studentId': studentId,
                      'studentName': studentName,
                      'className': className,
                      'section': section,
                      'score': score,
                    };

                    // Keep only the highest score for each student
                    if (!bestByStudent.containsKey(studentId) ||
                        score >
                            (bestByStudent[studentId]!['score'] as double)) {
                      bestByStudent[studentId] = result;
                    }
                  }

                  // Convert to list and sort by score descending
                  final List<Map<String, Object?>> results = bestByStudent
                      .values
                      .toList();

                  results.sort(
                    (a, b) =>
                        (b['score'] as double).compareTo(a['score'] as double),
                  );

                  // Compute award ranks (only for strictly positive scores)
                  int awardCounter = 0;
                  for (final r in results) {
                    final s = (r['score'] as double);
                    if (s > 0) {
                      awardCounter += 1;
                      r['awardRank'] = awardCounter; // 1,2,3,... for >0 scores
                    } else {
                      r['awardRank'] = null; // no medal for zero/not attended
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: results.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final result = results[index];
                        final isCurrentUser =
                            result['studentId'] == currentStudentId;

                        return _buildUserRow(
                          index + 1,
                          result,
                          isCurrentUser,
                          isDark,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserRow(
    int rank,
    Map<String, dynamic> data,
    bool isHighlighted,
    bool isDark,
  ) {
    final name = isHighlighted ? 'You' : (data['studentName'] as String);
    final className = data['className'] as String;
    final section = data['section'] as String;
    final score = (data['score'] as double).round();
    final int? awardRank = data['awardRank'] as int?; // null => no medal

    String classInfo = '';
    if (className.isNotEmpty && section.isNotEmpty) {
      classInfo = '$className, Section $section';
    } else if (className.isNotEmpty) {
      classInfo = className;
    }

    return Container(
      decoration: BoxDecoration(
        color: isHighlighted
            ? const Color(0xFFFF7B00).withOpacity(0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Rank Badge (medal only if awardRank is 1..3 and score > 0)
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getRankColor(awardRank, isDark),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: _getRankDisplay(rank, awardRank, isDark),
          ),
          const SizedBox(width: 16),
          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1A1D21),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (classInfo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    classInfo,
                    style: TextStyle(
                      color: isDark ? const Color(0xFFA1A1AA) : Colors.black54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Score Badge
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF7B00),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  '$score',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getRankColor(int? awardRank, bool isDark) {
    // Only award colors for top 3 with positive scores
    switch (awardRank) {
      case 1:
        return const Color(0xFFFBBF24); // Gold
      case 2:
        return const Color(0xFFCBD5E1); // Silver
      case 3:
        return const Color(0xFFD97706); // Bronze
      default:
        return isDark
            ? const Color(0xFF3F3F46)
            : const Color(0xFFE5E7EB); // Gray
    }
  }

  Widget _getRankDisplay(int displayRank, int? awardRank, bool isDark) {
    // Show medal emoji only if awardRank is 1..3 (score > 0)
    switch (awardRank) {
      case 1:
        return const Text('🥇', style: TextStyle(fontSize: 24));
      case 2:
        return const Text('🥈', style: TextStyle(fontSize: 24));
      case 3:
        return const Text('🥉', style: TextStyle(fontSize: 24));
      default:
        return Text(
          '$displayRank',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1A1D21),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        );
    }
  }
}
