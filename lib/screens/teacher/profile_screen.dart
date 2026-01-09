import 'dart:ui';
import 'package:flutter/material.dart';
import '../../utils/feedback_handler.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/session_manager.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/teacher_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  String? _error;

  // Dynamic profile data
  Map<String, dynamic>? _teacherData;
  int _classesManaged = 0;
  String? _currentUserId; // Store user ID for stream query

  // Theme helpers
  Color get _primary => const Color(0xFF8B5CF6);
  Color _surface(BuildContext context) => Theme.of(context).cardColor;
  Color _onSurface(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  Color _muted(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.65) ??
      Colors.grey;

  @override
  void initState() {
    super.initState();
    // Defer heavy initialization to post-frame to avoid build-phase setState warnings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfileData();
    });
  }

  Future<void> _loadProfileData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.initializeAuth();
      final user = authProvider.currentUser;
      // ignore: avoid_print
      print('[Profile] init for user: ${user?.email}');

      if (user == null) {
        setState(() {
          _error = 'No user logged in';
          _isLoading = false;
        });
        return;
      }

      // Fetch teacher document by email
      final teacherService = TeacherService();
      final teacherData = await teacherService.getTeacherByEmail(user.email);
      if (teacherData == null) {
        setState(() {
          _error = 'Teacher profile not found';
          _isLoading = false;
        });
        return;
      }

      // Compute classes handled
      final sections = teacherData['sections'] ?? teacherData['section'];
      final classesFormatted = teacherService.getTeacherClasses(
        teacherData['classesHandled'],
        sections,
        classAssignments: teacherData['classAssignments'],
      );
      final classesManaged = classesFormatted.length;

      setState(() {
        _teacherData = teacherData;
        _classesManaged = classesManaged;
        _currentUserId = user.uid;
        _isLoading = false;
      });
    } catch (e) {
      // ignore: avoid_print
      print('❌ [Profile] load error: $e');
      setState(() {
        _error = 'Failed to load profile';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_primary),
              ),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: _muted(context))),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadProfileData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 100),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildProfileHeader(),
                          const SizedBox(height: 24),
                          _buildTeachingOverview(),
                          const SizedBox(height: 24),
                          _buildPersonalInformation(),
                          const SizedBox(height: 24),
                          _buildAccountSettings(),
                          const SizedBox(height: 24),
                          _buildAppPreferences(),
                          const SizedBox(height: 16),
                          _buildLogoutButton(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      color: _onSurface(context),
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'My Profile',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _onSurface(context),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 64,
                          height: 2,
                          decoration: BoxDecoration(
                            color: _primary.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(1),
                            boxShadow: [
                              BoxShadow(
                                color: _primary.withOpacity(0.3),
                                blurRadius: 8,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final teacherName = _teacherData?['teacherName']?.toString().trim();
    final displayName = (teacherName != null && teacherName.isNotEmpty)
        ? teacherName
        : (user?.name ?? 'Teacher');
    final department =
        _teacherData?['department']?.toString() ??
        (_teacherData?['subjectsHandled'] is List
            ? (_teacherData!['subjectsHandled'] as List).join(', ')
            : _teacherData?['subjectsHandled']?.toString() ?? '');
    final schoolCode =
        _teacherData?['schoolCode']?.toString() ?? user?.instituteId ?? '';
    final profileImage = user?.profileImage;

    // Get initials for avatar fallback
    final nameParts = displayName.split(' ');
    final initials = nameParts.length >= 2
        ? '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase()
        : displayName
              .substring(0, displayName.length >= 2 ? 2 : 1)
              .toUpperCase();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _primary.withOpacity(0.12),
              border: Border.all(color: _primary.withOpacity(0.3), width: 2),
            ),
            child: ClipOval(
              child: (profileImage != null && profileImage.isNotEmpty)
                  ? Image.network(
                      profileImage,
                      width: 128,
                      height: 128,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildInitialsAvatar(initials),
                    )
                  : _buildInitialsAvatar(initials),
            ),
          ),
          const SizedBox(height: 16),
          // Name
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _onSurface(context),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          // Department/Subject
          Text(
            department.isNotEmpty ? department : 'Teacher',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: _muted(context)),
          ),
          if (schoolCode.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'School Code: $schoolCode',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: _muted(context).withOpacity(0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInitialsAvatar(String initials) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.bold,
          color: _primary,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _buildTeachingOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Teaching Overview',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _onSurface(context),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.school_outlined,
                value: '$_classesManaged',
                label: 'Classes Managed',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _currentUserId != null
                  ? StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('scheduledTests')
                          .where('teacherId', isEqualTo: _currentUserId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        final testCount = snapshot.hasData
                            ? snapshot.data!.docs.length
                            : 0;
                        return _buildStatCard(
                          icon: Icons.assignment_outlined,
                          value: '$testCount',
                          label: 'Tests Conducted',
                        );
                      },
                    )
                  : _buildStatCard(
                      icon: Icons.assignment_outlined,
                      value: '0',
                      label: 'Tests Conducted',
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.15 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: _primary, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: _onSurface(context),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _muted(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInformation() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;

    // Get email from auth user or teacherData
    final email = user?.email ?? _teacherData?['email'] ?? 'N/A';
    final phone =
        user?.phone ?? _teacherData?['phone'] ?? _teacherData?['phoneNumber'];

    final department =
        _teacherData?['department']?.toString() ??
        (_teacherData?['subjectsHandled'] is List
            ? (_teacherData!['subjectsHandled'] as List).join(', ')
            : _teacherData?['subjectsHandled']?.toString());

    final infoItems = <Map<String, dynamic>>[
      {'icon': Icons.mail_outline, 'label': 'Email', 'value': email},
      if (phone != null && phone.toString().isNotEmpty)
        {
          'icon': Icons.phone_outlined,
          'label': 'Phone Number',
          'value': phone.toString(),
        },
      if (department != null && department.isNotEmpty)
        {
          'icon': Icons.work_outline,
          'label': 'Department',
          'value': department,
        },
      if (_teacherData?['experience'] != null &&
          _teacherData!['experience'].toString().isNotEmpty)
        {
          'icon': Icons.timeline_outlined,
          'label': 'Experience',
          'value': '${_teacherData!['experience']} years',
        },
      if (_teacherData?['qualification'] != null &&
          _teacherData!['qualification'].toString().isNotEmpty)
        {
          'icon': Icons.school_outlined,
          'label': 'Qualification',
          'value': _teacherData!['qualification'].toString(),
        },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Personal Information',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _onSurface(context),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _surface(context),
            border: Border(
              left: BorderSide(color: _primary, width: 4),
              top: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.3),
              ),
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.3),
              ),
              right: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.3),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(
                  Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.06,
                ),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            child: Column(
              children: infoItems.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final isLast = index == infoItems.length - 1;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : Border(
                            bottom: BorderSide(
                              color: Theme.of(
                                context,
                              ).dividerColor.withOpacity(0.2),
                            ),
                          ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item['icon'] as IconData,
                        color: _muted(context),
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['label'] as String,
                              style: TextStyle(
                                fontSize: 14,
                                color: _muted(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item['value'] as String,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: _onSurface(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSettings() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settingsItems = [
      {
        'icon': Icons.star_outline,
        'label': 'My Highlights',
        'route': '/my-highlights',
      },
      {'icon': Icons.lock_outline, 'label': 'Change Password'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account Settings',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _onSurface(context),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 16),
        Column(
          children: settingsItems.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    final route = item['route'] as String?;
                    if (route != null) {
                      Navigator.pushNamed(context, route);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(item['label'] as String)),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _surface(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).dividerColor.withOpacity(0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.15 : 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: _primary.withOpacity(0.12),
                          ),
                          child: Icon(
                            item['icon'] as IconData,
                            color: _primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            item['label'] as String,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: _onSurface(context),
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: _muted(context),
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAppPreferences() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'App Preferences',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _onSurface(context),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 16),
        Column(
          children: [
            _buildThemeOptionCard('Light', false),
            const SizedBox(height: 12),
            _buildThemeOptionCard('Dark', true),
            const SizedBox(height: 12),
            _buildThemeOptionCard('System Default', null),
          ],
        ),
      ],
    );
  }

  Widget _buildThemeOptionCard(String label, bool? isDarkTheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);

    final targetMode = isDarkTheme == null
        ? ThemeMode.system
        : isDarkTheme
        ? ThemeMode.dark
        : ThemeMode.light;

    final isSelected = themeProvider.themeMode == targetMode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          themeProvider.setThemeMode(targetMode);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? _primary.withOpacity(0.1) : _surface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? _primary
                  : Theme.of(context).dividerColor.withOpacity(0.3),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.15 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _primary.withOpacity(0.12),
                ),
                child: Icon(
                  isDarkTheme == null
                      ? Icons.brightness_auto
                      : isDarkTheme
                      ? Icons.dark_mode
                      : Icons.light_mode,
                  color: _primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: _onSurface(context),
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: _primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showLogoutDialog,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _primary.withOpacity(isDark ? 0.4 : 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'Logout',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => const _LogoutConfirmationDialog(),
    ).then((confirmed) {
      if (confirmed == true) {
        _performLogout();
      }
    });
  }

  Future<void> _performLogout() async {
    try {
      // Clear session
      await SessionManager.clearLoginSession();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/role-selection');
        showSuccessSnackbar(
          context,
          'Logged out successfully',
          role: 'teacher',
        );
      }
    } catch (e) {
      print('Error during logout: $e');
      if (mounted) {
        showErrorDialog(
          context,
          getFriendlyErrorMessage(e),
          role: 'teacher',
          title: 'Logout Failed',
        );
      }
    }
  }
}

/// 🎨 Attractive Logout Confirmation Dialog (Teacher Theme)
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
                // Icon header with gradient background (Teacher violet theme)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFA78BFA), Color(0xFF7B61FF)],
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

                          // Logout button (Teacher violet theme)
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFA78BFA),
                                    Color(0xFF7B61FF),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF7B61FF,
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
