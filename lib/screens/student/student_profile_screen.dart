import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/daily_challenge_provider.dart';
import '../../providers/student_provider.dart';
import '../../services/leaderboard_service.dart';
import '../../services/student_service.dart';
import '../../services/firestore_service.dart';
import '../../models/student_model.dart';
import '../../models/performance_model.dart';

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  final _leaderboardService = LeaderboardService();
  final _studentService = StudentService();
  Future<StudentStats>? _statsFuture;
  StudentModel? _studentData;
  bool _isLoadingStudent = true;
  // Live performance + attendance
  double? _attendancePct;
  bool _attendanceLoading = true;
  int? _classRank; // from leaderboard stats (static until refresh)

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authProvider = Provider.of<AuthProvider>(context);
    final uid = authProvider.currentUser?.uid;
    if (uid != null) {
      _statsFuture ??= _leaderboardService.getStudentStats(
        studentId: uid,
        email: authProvider.currentUser?.email,
      );
      _loadStudentData(uid);
    }
  }

  Future<void> _loadStudentData(String uid) async {
    try {
      final data = await _studentService.getCurrentStudent();
      if (mounted) {
        setState(() {
          _studentData = data;
          _isLoadingStudent = false;
        });
      }
      // After loading student data, compute attendance once
      await _fetchAttendancePercentage();
      // Resolve class rank from stats future
      final stats = await _statsFuture;
      if (mounted) setState(() => _classRank = stats?.classRank);
    } catch (e) {
      print('Error loading student data: $e');
      if (mounted) {
        setState(() {
          _isLoadingStudent = false;
        });
      }
    }
  }

  Future<void> _fetchAttendancePercentage() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final schoolCode = authProvider.currentUser?.instituteId ?? '';
      if (schoolCode.isEmpty) {
        setState(() => _attendanceLoading = false);
        return;
      }
      final className =
          _studentData?.className; // e.g. "Grade 10" or "Grade 10 - B"
      if (className == null || className.isEmpty) {
        setState(() => _attendanceLoading = false);
        return;
      }
      final gradeMatch = RegExp(r'Grade\s+(\d+)').firstMatch(className);
      final sectionMatch = RegExp(r'-\s*([A-Za-z])').firstMatch(className);
      final grade = gradeMatch?.group(1);
      final section = sectionMatch?.group(1); // may be null
      if (grade == null) {
        setState(() => _attendanceLoading = false);
        return;
      }
      var query = FirebaseFirestore.instance
          .collection('attendance')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('standard', isEqualTo: grade);
      if (section != null && section.isNotEmpty) {
        query = query.where('section', isEqualTo: section);
      }
      final snapshot = await query.limit(120).get();
      int total = 0;
      int present = 0;
      for (final doc in snapshot.docs) {
        final students = doc.data()['students'] as Map<String, dynamic>?;
        if (students == null) continue;
        // Direct lookup by auth UID (simplified schema)
        final info = students[_studentData?.uid] as Map<String, dynamic>?;
        if (info == null) continue; // student not found in this attendance doc
        total++;
        if ((info['status']?.toString().toLowerCase() ?? 'present') ==
            'present') {
          present++;
        }
      }
      if (total > 0) _attendancePct = (present / total * 100).clamp(0, 100);
    } catch (e) {
      print('⚠️ attendance fetch error (profile): $e');
    } finally {
      if (mounted) setState(() => _attendanceLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildProfileHeader(user),
                    _buildStatsCards(),
                    _buildPersonalInfoSection(user),
                    const SizedBox(height: 80), // Bottom nav spacing
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withOpacity(0.85),
      ),
      child: Row(
        children: [
          // Left spacer (to balance settings button on right)
          const SizedBox(width: 40),
          Expanded(
            child: Text(
              'My Profile',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings coming soon')),
              );
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.cardColor.withOpacity(0.4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.settings,
                size: 22,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(dynamic user) {
    final theme = Theme.of(context);
    final String name =
        _studentData?.name ??
        user?.name ??
        user?.email?.split('@').first ??
        'Student';
    final String? imageUrl = _studentData?.photoUrl ?? user?.profileImage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: _isLoadingStudent
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Avatar
                Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.cardColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(color: theme.cardColor, width: 4),
                  ),
                  child: ClipOval(
                    child: imageUrl != null
                        ? Image.network(imageUrl, fit: BoxFit.cover)
                        : Center(
                            child: Text(
                              _initialsFromName(name),
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF8A00),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                _buildClassAndSectionBadges(theme),
              ],
            ),
    );
  }

  Widget _buildClassAndSectionBadges(ThemeData theme) {
    if (_studentData?.className == null) return const SizedBox.shrink();
    String standard = '';
    String section = _studentData?.section ?? '';
    if (_studentData!.className!.isNotEmpty) {
      final parts = _studentData!.className!.split(' - ');
      if (parts.isNotEmpty) {
        standard = 'Grade ${parts[0].trim()}';
        if (parts.length > 1 && section.isEmpty) section = parts[1].trim();
      }
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (standard.isNotEmpty) _badge(standard),
        if (section.isNotEmpty) ...[
          const SizedBox(width: 8),
          _badge('Section $section'),
        ],
      ],
    );
  }

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Color(0xFFA3A3A3),
      ),
    ),
  );

  String _initialsFromName(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return 'ST';
    if (parts.length == 1) return parts.first.substring(0, 2).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Widget _buildStatsCards() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uid = authProvider.currentUser?.uid;
    if (uid == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<PerformanceModel?>(
      stream: FirestoreService().getPerformanceStream(uid),
      builder: (context, snapshot) {
        final perf = snapshot.data;
        final testsTaken = perf?.submissions.length ?? 0;
        final avg = perf?.averageScore ?? 0.0;
        final latest = (perf?.submissions.isNotEmpty ?? false)
            ? perf!.submissions.last.percentage
            : avg;
        final rank = _classRank;
        final attendanceDisplay = _attendancePct != null
            ? '${_attendancePct!.round()}%'
            : _attendanceLoading
            ? '…'
            : '--';
        final stats = [
          {'label': 'Tests Taken', 'value': '$testsTaken'},
          {'label': 'Average Score', 'value': '${avg.toStringAsFixed(1)}%'},
          {'label': 'Class Rank', 'value': rank != null ? '$rank' : '--'},
          {'label': 'Attendance', 'value': attendanceDisplay},
          {'label': 'Latest', 'value': '${latest.toStringAsFixed(1)}%'},
        ];
        // Limit to first four stats per new design (exclude Latest)
        final displayStats = stats.take(4).toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth =
                  (constraints.maxWidth - 12) / 2; // 2 columns gap 12
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: displayStats
                    .map((s) => _statCell(s['label']!, s['value']!, itemWidth))
                    .toList(),
              );
            },
          ),
        );
      },
    );
  }

  Widget _statCell(String label, String value, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFFA3A3A3),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoSection(dynamic user) {
    final theme = Theme.of(context);
    final String email = _studentData?.email ?? user?.email ?? 'N/A';
    final String phone = _studentData?.phone ?? 'N/A';
    final String schoolName = _studentData?.schoolName ?? 'N/A';
    final String parentPhone = _studentData?.parentPhone ?? 'N/A';

    return Column(
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Personal Information',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        // Info table
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF3A3A3A)),
            ),
            child: Column(
              children: [
                _infoRow('Email', email, top: true),
                _infoRow('Phone', phone),
                _infoRow('School Name', schoolName),
                _infoRow('Guardian Contact', parentPhone, bottom: true),
              ],
            ),
          ),
        ),
        // Logout button
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildLogoutButton(),
        ),
      ],
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _onLogout,
        icon: const Icon(Icons.logout, color: Color(0xFFE5484D)),
        label: const Text(
          'Logout',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFFE5484D),
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFE5484D), width: 2),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: const Color(0xFFE5484D),
        ),
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    bool top = false,
    bool bottom = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: bottom
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFF3A3A3A), width: 1),
              ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFFA3A3A3),
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Removed photo change overlay per new design; keep helper stub if needed in future.

  // _onEditProfile removed (unused)

  Future<void> _onLogout() async {
    // Show attractive confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) => _LogoutConfirmationDialog(),
    );

    if (confirmed != true) return;

    try {
      if (mounted) {
        // Clear all provider states before sign out
        final dailyChallengeProvider = Provider.of<DailyChallengeProvider>(
          context,
          listen: false,
        );
        await dailyChallengeProvider.clearAllState();

        final studentProvider = Provider.of<StudentProvider>(
          context,
          listen: false,
        );
        await studentProvider.clear();

        // Clear auth provider and SharedPreferences (handled in signOut)
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        await authProvider.signOut();
      }

      // Navigate to role selection and clear all previous routes
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/role-selection', (route) => false);
      }
    } catch (e) {
      print('Error during logout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error logging out. Please try again.')),
        );
      }
    }
  }
}

/// 🎨 Attractive Logout Confirmation Dialog
class _LogoutConfirmationDialog extends StatefulWidget {
  const _LogoutConfirmationDialog();

  @override
  State<_LogoutConfirmationDialog> createState() =>
      _LogoutConfirmationDialogState();
}

class _LogoutConfirmationDialogState extends State<_LogoutConfirmationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon header with gradient background
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFfcb045), Color(0xFFf27f0d)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        'Logout',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Are you sure you want to logout?\nYou will need to sign in again to access your account.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white70 : Colors.black54,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Action buttons
                      Row(
                        children: [
                          // Cancel button
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.3)
                                      : Colors.grey.shade300,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Logout button
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFfcb045),
                                    Color(0xFFf27f0d),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFf27f0d,
                                    ).withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Logout',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Bottom nav is centralized in StudentBottomNav widget.

class _EditProfileDialog extends StatefulWidget {
  final StudentModel studentData;
  final Function(Map<String, String?>) onSave;

  const _EditProfileDialog({required this.studentData, required this.onSave});

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _schoolController;
  late TextEditingController _parentPhoneController;
  late TextEditingController _classController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.studentData.name);
    _phoneController = TextEditingController(
      text: widget.studentData.phone ?? '',
    );
    _schoolController = TextEditingController(
      text: widget.studentData.schoolName ?? '',
    );
    _parentPhoneController = TextEditingController(
      text: widget.studentData.parentPhone ?? '',
    );
    _classController = TextEditingController(
      text: widget.studentData.className ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _schoolController.dispose();
    _parentPhoneController.dispose();
    _classController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        'Edit Profile',
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _schoolController,
              decoration: InputDecoration(
                labelText: 'School Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.school),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _parentPhoneController,
              decoration: InputDecoration(
                labelText: 'Parent Phone Number',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.contact_phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _classController,
              decoration: InputDecoration(
                labelText: 'Class',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.class_),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            final updatedData = {
              'name': _nameController.text.trim(),
              'phone': _phoneController.text.trim().isEmpty
                  ? null
                  : _phoneController.text.trim(),
              'schoolName': _schoolController.text.trim().isEmpty
                  ? null
                  : _schoolController.text.trim(),
              'parentPhone': _parentPhoneController.text.trim().isEmpty
                  ? null
                  : _parentPhoneController.text.trim(),
              'className': _classController.text.trim().isEmpty
                  ? null
                  : _classController.text.trim(),
            };

            widget.onSave(updatedData);
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF97316),
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
