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

            // Recent Activity (if available)
            // TODO: Implement when backend provides recent activity data
            // _buildRecentActivity(),
            // const SizedBox(height: 16),

            // Notes Section
            _buildNotesSection(context),
          ],
        ),
      ),
    );
  }

  Color _getBg(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF0B1113) : const Color(0xFFF8FAFC);
  }

  Color _getCardBg(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF151E28) : const Color(0xFFFFFFFF);
  }

  Color _getPanel(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF1A1F2E) : const Color(0xFFFFFFFF);
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
    final cardBg = _getCardBg(context);
    final border = _getBorder(context);
    final primary = _getPrimary();
    final textPrimary = _getTextPrimary(context);
    final textSecondary = _getTextSecondary(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: primary, width: 2),
            ),
            child: ClipOval(
              child: staff.imageUrl.isNotEmpty
                  ? Image.network(
                      staff.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _buildAvatarPlaceholder(context),
                    )
                  : _buildAvatarPlaceholder(context),
            ),
          ),
          const SizedBox(height: 16),

          // Name
          Text(
            staff.name,
            style: TextStyle(
              color: textPrimary,
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
              color: textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: staff.statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: staff.statusColor, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: staff.statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  staff.status,
                  style: TextStyle(
                    color: staff.statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPlaceholder(BuildContext context) {
    final primary = _getPrimary();
    return Container(
      color: primary.withOpacity(0.2),
      child: Icon(Icons.person, color: primary, size: 40),
    );
  }

  Widget _buildContactCard(BuildContext context) {
    final cardBg = _getCardBg(context);
    final border = _getBorder(context);
    final textPrimary = _getTextPrimary(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contact Information',
            style: TextStyle(
              color: textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          if (staff.email.isNotEmpty) ...[
            _buildContactRow(
              context: context,
              icon: Icons.email_outlined,
              label: 'Email',
              value: staff.email,
              onCopy: () => _copyToClipboard(staff.email, 'Email'),
            ),
            const SizedBox(height: 14),
          ],
          if (staff.phone.isNotEmpty)
            _buildContactRow(
              context: context,
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: staff.phone,
              onCopy: () => _copyToClipboard(staff.phone, 'Phone'),
            ),
        ],
      ),
    );
  }

  Widget _buildContactRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onCopy,
  }) {
    final primary = _getPrimary();
    final textSecondary = _getTextSecondary(context);
    final iconColor = _getIconColor(context);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: textSecondary, fontSize: 12)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.copy, color: textSecondary, size: 18),
          onPressed: onCopy,
        ),
      ],
    );
  }

  Widget _buildAssignmentsSection(BuildContext context) {
    final textPrimary = _getTextPrimary(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assignments',
          style: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_hasSubjects())
              Expanded(
                child: _buildAssignmentCard(
                  context: context,
                  title: 'Subjects Handled',
                  items: staff.subjects.map(_parseSubject).toSet().toList(),
                  icon: Icons.menu_book,
                ),
              ),
            if (_hasSubjects() && _hasClasses()) const SizedBox(width: 12),
            if (_hasClasses())
              Expanded(
                child: _buildAssignmentCard(
                  context: context,
                  title: 'Classes',
                  items: staff.classes.map(_parseClass).toSet().toList(),
                  icon: Icons.class_,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAssignmentCard({
    required BuildContext context,
    required String title,
    required List<String> items,
    required IconData icon,
  }) {
    final cardBg = _getCardBg(context);
    final border = _getBorder(context);
    final primary = _getPrimary();
    final textSecondary = _getTextSecondary(context);
    final panel = _getPanel(context);
    final iconColor = _getIconColor(context);

    // Filter out "Not assigned" entries
    final validItems = items
        .where(
          (item) =>
              item.isNotEmpty &&
              !item.toLowerCase().contains('not assigned') &&
              !item.toLowerCase().contains('none'),
        )
        .toList();

    if (validItems.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: validItems
                .map(
                  (item) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: primary.withOpacity(0.3)),
                    ),
                    child: Text(
                      item,
                      style: TextStyle(
                        color: iconColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceSection(BuildContext context) {
    final cardBg = _getCardBg(context);
    final border = _getBorder(context);
    final primary = _getPrimary();
    final textPrimary = _getTextPrimary(context);
    final textSecondary = _getTextSecondary(context);

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
            color: textPrimary,
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
                      color: cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: border, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          stat['icon'] as IconData,
                          color: primary,
                          size: 24,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          stat['value'] as String,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stat['label'] as String,
                          style: TextStyle(color: textSecondary, fontSize: 12),
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

  Widget _buildNotesSection(BuildContext context) {
    final cardBg = _getCardBg(context);
    final border = _getBorder(context);
    final primary = _getPrimary();
    final textPrimary = _getTextPrimary(context);
    final textSecondary = _getTextSecondary(context);
    final panel = _getPanel(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.note_outlined, color: primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Notes',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'No notes available',
              style: TextStyle(
                color: textSecondary,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods
  bool _hasAssignments() => _hasSubjects() || _hasClasses();

  bool _hasSubjects() {
    return staff.subjects.isNotEmpty &&
        staff.subjects.any(
          (s) =>
              s.isNotEmpty &&
              !s.toLowerCase().contains('not assigned') &&
              !s.toLowerCase().contains('none'),
        );
  }

  bool _hasClasses() {
    return staff.classes.isNotEmpty &&
        staff.classes.any(
          (c) =>
              c.isNotEmpty &&
              !c.toLowerCase().contains('not assigned') &&
              !c.toLowerCase().contains('none'),
        );
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
