import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class StaffDetailsPage extends StatelessWidget {
  const StaffDetailsPage({super.key, required this.staff});

  final StaffMember staff;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _getBg(context),
      appBar: _buildAppBar(context),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header Card
            Center(child: _buildProfileHeader(context)),
            const SizedBox(height: 16),

            // Contact Information
            if (staff.email.isNotEmpty || staff.phone.isNotEmpty)
              _buildContactCard(context),
            if (staff.email.isNotEmpty || staff.phone.isNotEmpty)
              const SizedBox(height: 16),

            // Assignments (Subjects & Classes)
            if (_hasAssignments()) _buildAssignmentsSection(context),
            if (_hasAssignments()) const SizedBox(height: 16),

            // Performance Section (only if has data)
            if (_hasPerformanceData()) _buildPerformanceSection(context),
            if (_hasPerformanceData()) const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // Theme helper methods
  Color _getBg(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF0B1113) : const Color(0xFFF8FAFC);
  }

  Color _getCardBg(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF151E28) : Colors.white;
  }

  Color _getPanel(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF1A1F2E) : Colors.white;
  }

  Color _getPrimary() => const Color(0xFF146D7A);

  Color _getTextPrimary(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white : const Color(0xFF0F172A);
  }

  Color _getTextSecondary(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  }

  Color _getBorder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white10 : const Color(0xFFE2E8F0);
  }

  Color _getIconColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white : const Color(0xFF1E293B);
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: _getBg(context),
      elevation: 0,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new,
          color: _getIconColor(context),
          size: 20,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Staff Details',
        style: TextStyle(
          color: _getIconColor(context),
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        if (staff.phone.isNotEmpty)
          IconButton(
            icon: Icon(Icons.call, color: _getPrimary()),
            onPressed: () => _makeCall(staff.phone),
          ),
      ],
    );
  }

  Widget _buildProfileHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _getCardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _getBorder(context), width: 0.5),
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _getPrimary(), width: 2),
            ),
            child: ClipOval(
              child: staff.imageUrl.isNotEmpty
                  ? Image.network(
                      staff.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _buildAvatarPlaceholder(),
                    )
                  : _buildAvatarPlaceholder(),
            ),
          ),
          const SizedBox(height: 16),

          // Name
          Text(
            staff.name,
            style: TextStyle(
              color: _getTextPrimary(context),
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),

          // Role
          Text(
            staff.role,
            style: TextStyle(
              color: _getTextSecondary(context),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPlaceholder() {
    return Container(
      color: _getPrimary().withOpacity(0.2),
      child: Icon(Icons.person, color: _getPrimary(), size: 40),
    );
  }

  Widget _buildContactCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _getCardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _getBorder(context), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contact Information',
            style: TextStyle(
              color: _getTextPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          if (staff.email.isNotEmpty) ...[
            _buildContactRow(
              context,
              icon: Icons.email_outlined,
              label: 'Email',
              value: staff.email,
              onCopy: () => _copyToClipboard(staff.email, 'Email'),
            ),
            const SizedBox(height: 14),
          ],
          if (staff.phone.isNotEmpty)
            _buildContactRow(
              context,
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: staff.phone,
              onCopy: () => _copyToClipboard(staff.phone, 'Phone'),
            ),
        ],
      ),
    );
  }

  Widget _buildContactRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onCopy,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _getPrimary().withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _getPrimary(), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: _getTextSecondary(context),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: _getIconColor(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.copy, color: _getTextSecondary(context), size: 18),
          onPressed: onCopy,
        ),
      ],
    );
  }

  Widget _buildAssignmentsSection(BuildContext context) {
    final subjectClassMap = _buildSubjectClassMap();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assignments',
          style: TextStyle(
            color: _getTextPrimary(context),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _getCardBg(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _getBorder(context), width: 0.5),
          ),
          child: Column(
            children: subjectClassMap.entries.map((entry) {
              final subject = entry.key;
              final classes = entry.value;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getPanel(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getPrimary().withOpacity(0.18),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.menu_book, color: _getPrimary(), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            subject,
                            style: TextStyle(
                              color: _getTextPrimary(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: classes
                          .map(
                            (className) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _getCardBg(context),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _getPrimary().withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                className,
                                style: TextStyle(
                                  color: _getIconColor(context),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceSection(BuildContext context) {
    final stats = <Map<String, dynamic>>[];

    if (staff.stats.totalTests > 0) {
      stats.add({
        'label': 'Tests Conducted',
        'value': staff.stats.totalTests.toString(),
        'icon': Icons.assignment_outlined,
      });
    }

    if (staff.stats.studentsImpacted > 0) {
      stats.add({
        'label': 'Students Assigned',
        'value': staff.stats.studentsImpacted.toString(),
        'icon': Icons.groups_outlined,
      });
    }

    if (staff.stats.avgScore > 0) {
      stats.add({
        'label': 'Avg Performance',
        'value': '${staff.stats.avgScore}%',
        'icon': Icons.trending_up,
      });
    }

    if (stats.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance Snapshot',
          style: TextStyle(
            color: _getTextPrimary(context),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: stats
              .map(
                (stat) => Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: stat == stats.last ? 0 : 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _getCardBg(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _getBorder(context),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          stat['icon'] as IconData,
                          color: _getPrimary(),
                          size: 24,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          stat['value'] as String,
                          style: TextStyle(
                            color: _getTextPrimary(context),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stat['label'] as String,
                          style: TextStyle(
                            color: _getTextSecondary(context),
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  // Helper methods
  bool _hasAssignments() => _hasSubjects() || _hasClasses();

  Map<String, List<String>> _buildSubjectClassMap() {
    final subjectToClasses = <String, Set<String>>{};
    final allEntries = <String>[...staff.subjects, ...staff.classes];

    for (final entry in allEntries) {
      if (!_isValidAssignmentItem(entry)) continue;

      final subject = _parseSubject(entry);
      final className = _parseClass(entry);

      if (!_isValidAssignmentItem(subject) ||
          !_isValidAssignmentItem(className)) {
        continue;
      }

      (subjectToClasses[subject] ??= <String>{}).add(className);
    }

    // If assignments are split as plain lists, map each subject to all classes.
    if (subjectToClasses.isEmpty && _hasSubjects() && _hasClasses()) {
      final subjects = staff.subjects
          .where(_isValidAssignmentItem)
          .map(_parseSubject)
          .toSet();
      final classes = staff.classes
          .where(_isValidAssignmentItem)
          .map(_parseClass)
          .toSet()
          .toList();

      for (final subject in subjects) {
        subjectToClasses[subject] = classes.toSet();
      }
    }

    final sorted = <String, List<String>>{};
    final sortedSubjects = subjectToClasses.keys.toList()..sort();
    for (final subject in sortedSubjects) {
      final classes = subjectToClasses[subject]!.toList()..sort();
      sorted[subject] = classes;
    }
    return sorted;
  }

  bool _isValidAssignmentItem(String item) {
    final lower = item.toLowerCase().trim();
    return lower.isNotEmpty &&
        !lower.contains('not assigned') &&
        !lower.contains('none');
  }

  bool _hasSubjects() {
    return staff.subjects.isNotEmpty &&
        staff.subjects.any(_isValidAssignmentItem);
  }

  bool _hasClasses() {
    return staff.classes.isNotEmpty &&
        staff.classes.any(_isValidAssignmentItem);
  }

  // Parse subject name from "Grade 11: A, physics" -> "Physics"
  String _parseSubject(String item) {
    if (item.contains(',')) {
      final parts = item.split(',');
      if (parts.length > 1) {
        return parts[1].trim();
      }
    }
    return item;
  }

  // Parse class from "Grade 11: A, physics" -> "Grade 11: A"
  String _parseClass(String item) {
    if (item.contains(',')) {
      final parts = item.split(',');
      return parts[0].trim();
    }
    return item;
  }

  bool _hasPerformanceData() {
    return staff.stats.totalTests > 0 ||
        staff.stats.studentsImpacted > 0 ||
        staff.stats.avgScore > 0;
  }

  // Actions
  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    // Note: In a real app, show a SnackBar here
  }

  void _makeCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

// Data model classes
class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.status,
    required this.role,
    required this.roleKey,
    required this.imageUrl,
    required this.subjects,
    required this.classes,
    required this.stats,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String status;
  final String role;
  final String roleKey;
  final String imageUrl;
  final List<String> subjects;
  final List<String> classes;
  final StaffStats stats;

  Color get statusColor {
    switch (status.toLowerCase()) {
      case 'in class':
        return Colors.green;
      case 'free period':
        return Colors.grey;
      case 'absent':
        return Colors.red;
      case 'on leave':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }
}

class StaffStats {
  const StaffStats({
    required this.totalTests,
    required this.avgScore,
    required this.studentsImpacted,
  });

  final int totalTests;
  final int avgScore;
  final int studentsImpacted;
}
