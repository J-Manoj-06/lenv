import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class StaffDetailsPage extends StatelessWidget {
  const StaffDetailsPage({super.key, required this.staff});

  final StaffMember staff;

  // Colors
  static const _bg = Color(0xFF0B1113);
  static const _primary = Color(0xFF1E88E5);
  static const _panel = Color(0xFF1A1F2E);
  static const _slate400 = Color(0xFF94A3B8);
  static const _cardBg = Color(0xFF151E28);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Staff Details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (staff.phone.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.call, color: _primary),
              onPressed: () => _makeCall(staff.phone),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header Card
            Center(child: _buildProfileHeader()),
            const SizedBox(height: 16),

            // Contact Information
            if (staff.email.isNotEmpty || staff.phone.isNotEmpty)
              _buildContactCard(),
            if (staff.email.isNotEmpty || staff.phone.isNotEmpty)
              const SizedBox(height: 16),

            // Assignments (Subjects & Classes)
            if (_hasAssignments()) _buildAssignmentsSection(),
            if (_hasAssignments()) const SizedBox(height: 16),

            // Performance Section (only if has data)
            if (_hasPerformanceData()) _buildPerformanceSection(),
            if (_hasPerformanceData()) const SizedBox(height: 16),

            // Recent Activity (if available)
            // TODO: Implement when backend provides recent activity data
            // _buildRecentActivity(),
            // const SizedBox(height: 16),

            // Notes Section
            _buildNotesSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10, width: 0.5),
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _primary, width: 2),
            ),
            child: ClipOval(
              child: staff.imageUrl.isNotEmpty
                  ? Image.network(
                      staff.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildAvatarPlaceholder(),
                    )
                  : _buildAvatarPlaceholder(),
            ),
          ),
          const SizedBox(height: 16),

          // Name
          Text(
            staff.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),

          // Role
          Text(
            staff.role,
            style: const TextStyle(
              color: _slate400,
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

  Widget _buildAvatarPlaceholder() {
    return Container(
      color: _primary.withOpacity(0.2),
      child: const Icon(Icons.person, color: _primary, size: 40),
    );
  }

  Widget _buildContactCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contact Information',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          if (staff.email.isNotEmpty) ...[
            _buildContactRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: staff.email,
              onCopy: () => _copyToClipboard(staff.email, 'Email'),
            ),
            const SizedBox(height: 14),
          ],
          if (staff.phone.isNotEmpty)
            _buildContactRow(
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
            color: _primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: _slate400, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, color: _slate400, size: 18),
          onPressed: onCopy,
        ),
      ],
    );
  }

  Widget _buildAssignmentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Assignments',
          style: TextStyle(
            color: Colors.white,
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
                  title: 'Subjects Handled',
                  items: staff.subjects.map(_parseSubject).toSet().toList(),
                  icon: Icons.menu_book,
                ),
              ),
            if (_hasSubjects() && _hasClasses()) const SizedBox(width: 12),
            if (_hasClasses())
              Expanded(
                child: _buildAssignmentCard(
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
    required String title,
    required List<String> items,
    required IconData icon,
  }) {
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
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _slate400,
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
                      color: _panel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _primary.withOpacity(0.3)),
                    ),
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Colors.white,
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

  Widget _buildPerformanceSection() {
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
        const Text(
          'Performance Snapshot',
          style: TextStyle(
            color: Colors.white,
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
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          stat['icon'] as IconData,
                          color: _primary,
                          size: 24,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          stat['value'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stat['label'] as String,
                          style: const TextStyle(
                            color: _slate400,
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

  Widget _buildNotesSection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.note_outlined, color: _primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Notes',
                style: TextStyle(
                  color: Colors.white,
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
              color: _panel,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'No notes available',
              style: TextStyle(
                color: _slate400,
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
