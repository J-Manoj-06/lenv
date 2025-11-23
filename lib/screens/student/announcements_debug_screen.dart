import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/student_provider.dart';

/// Debug screen to help diagnose announcement visibility issues
/// Navigate to this screen from student dashboard to see all relevant data
class AnnouncementsDebugScreen extends StatelessWidget {
  const AnnouncementsDebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final studentProvider = Provider.of<StudentProvider>(context);
    final student = studentProvider.currentStudent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📢 Announcements Debug'),
        backgroundColor: const Color(0xFFF27F0D),
      ),
      body: student == null
          ? const Center(child: Text('No student data'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection('Student Information', [
                    _buildRow('Email', student.email),
                    _buildRow('Name', student.name),
                    _buildRow('School ID', student.schoolId ?? 'NULL'),
                    _buildRow('School Name', student.schoolName ?? 'NULL'),
                    _buildRow('Class Name', student.className ?? 'NULL'),
                  ]),
                  const SizedBox(height: 24),
                  _buildSection('Parsed Class Info', [
                    _buildRow('Standard', _parseStandard(student.className)),
                    _buildRow('Section', _parseSection(student.className)),
                    _buildRow('Combined', _parseCombined(student.className)),
                  ]),
                  const SizedBox(height: 24),
                  _buildAnnouncementsSection(student),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFF27F0D),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: value == 'NULL' || value.isEmpty
                    ? Colors.red
                    : Colors.black,
                fontWeight: value == 'NULL' || value.isEmpty
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsSection(student) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('class_highlights')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildSection('Announcements in Database', [
            const Text(
              'No announcements found in database',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ]);
        }

        final announcements = snapshot.data!.docs;
        final studentSchoolId = student.schoolId ?? '';

        return _buildSection(
          'Announcements in Database (${announcements.length})',
          [
            Text(
              'Showing last ${announcements.length} announcements:',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ...announcements.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final instituteId = data['instituteId'] ?? '';
              final audienceType = data['audienceType'] ?? '';
              final teacherName = data['teacherName'] ?? '';
              final text = data['text'] ?? '';
              final matches = instituteId == studentSchoolId;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: matches ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: matches ? Colors.green : Colors.red,
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          matches ? Icons.check_circle : Icons.cancel,
                          color: matches ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            matches ? 'MATCH ✓' : 'NO MATCH ✗',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: matches ? Colors.green : Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    _buildRow('Teacher', teacherName),
                    _buildRow('Institute ID', instituteId),
                    _buildRow('Audience Type', audienceType),
                    _buildRow(
                      'Text',
                      text.substring(0, text.length > 50 ? 50 : text.length),
                    ),
                    _buildRow('Matches Student', matches ? 'YES' : 'NO'),
                    if (!matches)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '❌ Student schoolId "$studentSchoolId" ≠ Announcement instituteId "$instituteId"',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  String _parseStandard(String? className) {
    if (className == null || className.isEmpty) return 'NULL';

    if (className.contains('-')) {
      final parts = className.split('-').map((e) => e.trim()).toList();
      if (parts.length == 2) {
        return parts[0].replaceAll('Grade', '').trim();
      }
    } else if (className.contains(' ')) {
      return className.replaceAll('Grade', '').trim();
    } else {
      final match = RegExp(r'^(\d+)([A-Z])$').firstMatch(className);
      if (match != null) {
        return match.group(1) ?? '';
      }
      return className;
    }
    return 'Could not parse';
  }

  String _parseSection(String? className) {
    if (className == null || className.isEmpty) return 'NULL';

    if (className.contains('-')) {
      final parts = className.split('-').map((e) => e.trim()).toList();
      if (parts.length == 2) {
        return parts[1].trim();
      }
    } else {
      final match = RegExp(r'^(\d+)([A-Z])$').firstMatch(className);
      if (match != null) {
        return match.group(2) ?? '';
      }
    }
    return 'N/A';
  }

  String _parseCombined(String? className) {
    final standard = _parseStandard(className);
    final section = _parseSection(className);
    if (section == 'N/A' || section == 'NULL') return standard;
    return '$standard$section';
  }
}
