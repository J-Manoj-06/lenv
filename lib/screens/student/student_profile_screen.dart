import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/leaderboard_service.dart';
import '../../services/student_service.dart';
import '../../models/student_model.dart';
import '../../utils/session_manager.dart';
import '../../widgets/student_bottom_nav.dart';

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
    } catch (e) {
      print('Error loading student data: $e');
      if (mounted) {
        setState(() {
          _isLoadingStudent = false;
        });
      }
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
      bottomNavigationBar: const StudentBottomNav(currentIndex: 4),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF97316),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(
              child: Icon(Icons.school, color: Colors.white, size: 28),
            ),
          ),
          // Title
          Expanded(
            child: Text(
              'My Profile',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 48),
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
      padding: const EdgeInsets.all(16),
      child: _isLoadingStudent
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Profile image with camera button
                Stack(
                  children: [
                    Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(64),
                        image: imageUrl != null
                            ? DecorationImage(
                                image: NetworkImage(imageUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                        color: imageUrl == null
                            ? theme.colorScheme.surfaceVariant
                            : null,
                      ),
                      child: imageUrl == null
                          ? Icon(
                              Icons.person,
                              size: 64,
                              color: theme.iconTheme.color?.withOpacity(0.6),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: _onChangePhoto,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF97316),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.photo_camera,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Name and class info
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_studentData?.className != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Class: ${_studentData!.className}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildStatsCards() {
    return FutureBuilder<StudentStats>(
      future: _statsFuture,
      builder: (context, snapshot) {
        final testsTaken = snapshot.data?.testsTaken ?? 0;
        final avg = snapshot.data?.averageScore ?? 0.0;
        final rank = snapshot.data?.classRank;
        final stats = [
          {'label': 'Tests Taken', 'value': '$testsTaken'},
          {'label': 'Average Score', 'value': '${avg.toStringAsFixed(1)}%'},
          {'label': 'Class Rank', 'value': rank != null ? '$rank' : '--'},
          {'label': 'Attendance', 'value': '--'},
        ];
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: stats.map((stat) => _buildStatCard(stat)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(Map<String, String> stat) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Two cards per row with spacing
    final cardWidth = (screenWidth - 48) / 2;

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stat['label']!, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            stat['value']!,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
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
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildInfoRow('Email', email, isFirst: true),
                _buildInfoRow('Phone', phone),
                _buildInfoRow('School Name', schoolName),
                _buildInfoRow('Parent Number', parentPhone, isLast: true),
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
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _onLogout,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout, color: theme.colorScheme.error, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Logout',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _onChangePhoto() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Change photo coming soon!')));
  }

  void _onEditProfile() {
    if (_studentData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for profile data to load')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _EditProfileDialog(
        studentData: _studentData!,
        onSave: (updatedData) async {
          try {
            await _studentService.updateStudentProfile(
              uid: _studentData!.uid,
              name: updatedData['name'],
              phone: updatedData['phone'],
              schoolName: updatedData['schoolName'],
              parentPhone: updatedData['parentPhone'],
              className: updatedData['className'],
            );

            // Reload data
            await _loadStudentData(_studentData!.uid);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile updated successfully!')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error updating profile: $e')),
              );
            }
          }
        },
      ),
    );
  }

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
      // Clear session from SharedPreferences
      await SessionManager.clearLoginSession();

      // Clear auth provider state
      if (mounted) {
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

  void _closeDialog(bool confirmed) {
    _animationController.reverse().then((_) {
      if (mounted) {
        Navigator.of(context).pop(confirmed);
      }
    });
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
                              onPressed: () => _closeDialog(false),
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
                                onPressed: () => _closeDialog(true),
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
