import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class PerTestLeaderboardDetail extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentStudentId = authProvider.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
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
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 24,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          'Leaderboard',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
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
                    '$testTitle${subject.isNotEmpty ? ' - $subject' : ''}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFA1A1AA),
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
                    .where('testId', isEqualTo: testId)
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
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(48),
                            ),
                            child: const Icon(
                              Icons.menu_book,
                              size: 48,
                              color: Color(0xFF52525B),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No students assigned yet',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Students will appear once test is assigned',
                            style: TextStyle(
                              color: Color(0xFF71717A),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Parse and sort results
                  final List<Map<String, dynamic>> results = snapshot.data!.docs
                      .map<Map<String, dynamic>>((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return {
                          'studentId': data['studentId'] as String? ?? '',
                          'studentName':
                              data['studentName'] as String? ?? 'Unknown',
                          'className': data['className'] as String? ?? '',
                          'section': data['section'] as String? ?? '',
                          'score': (data['score'] as num?)?.toDouble() ?? 0.0,
                        };
                      })
                      .toList();

                  // Sort by score descending
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

                  // Find current user's rank
                  int? currentUserRank;
                  Map<String, dynamic>? currentUserData;
                  for (int i = 0; i < results.length; i++) {
                    if (results[i]['studentId'] == currentStudentId) {
                      currentUserRank = i + 1;
                      currentUserData = results[i];
                      break;
                    }
                  }

                  return Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      children: [
                        // User's Highlighted Row
                        if (currentUserRank != null && currentUserData != null)
                          _buildUserRow(currentUserRank, currentUserData, true),

                        // Divider
                        if (currentUserRank != null && results.isNotEmpty)
                          Container(
                            height: 1,
                            color: const Color(0xFF333333),
                            margin: const EdgeInsets.symmetric(vertical: 8),
                          ),

                        // Leaderboard List
                        Expanded(
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: results.length,
                            separatorBuilder: (context, index) => Container(
                              height: 1,
                              color: const Color(0xFF333333),
                              margin: const EdgeInsets.only(left: 64),
                            ),
                            itemBuilder: (context, index) {
                              final result = results[index];
                              final isCurrentUser =
                                  result['studentId'] == currentStudentId;

                              // Skip current user if already shown at top
                              if (isCurrentUser && currentUserRank != null) {
                                return const SizedBox.shrink();
                              }

                              return _buildUserRow(index + 1, result, false);
                            },
                          ),
                        ),
                      ],
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
              color: _getRankColor(awardRank),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: _getRankDisplay(rank, awardRank),
          ),
          const SizedBox(width: 16),
          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (classInfo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    classInfo,
                    style: const TextStyle(
                      color: Color(0xFFA1A1AA),
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

  Color _getRankColor(int? awardRank) {
    // Only award colors for top 3 with positive scores
    switch (awardRank) {
      case 1:
        return const Color(0xFFFBBF24); // Gold
      case 2:
        return const Color(0xFFCBD5E1); // Silver
      case 3:
        return const Color(0xFFD97706); // Bronze
      default:
        return const Color(0xFF3F3F46); // Gray
    }
  }

  Widget _getRankDisplay(int displayRank, int? awardRank) {
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
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        );
    }
  }
}
