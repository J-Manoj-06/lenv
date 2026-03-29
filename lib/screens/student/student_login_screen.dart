import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../providers/auth_provider.dart';
import '../../providers/unread_count_provider.dart';
import '../../models/user_model.dart';
import '../../services/school_storage_service.dart';
import '../../services/student_usage_service.dart';
import '../../utils/session_manager.dart';
import '../../utils/feedback_handler.dart';
import '../../utils/lenv_snackbar.dart';
import '../auth/forgot_password_screen.dart';

class StudentLoginScreen extends StatefulWidget {
  const StudentLoginScreen({super.key});

  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _selectedSchool;
  String _selectedSchoolName = 'Selected school';
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  // Brand colors from HTML
  static const Color brandOrange = Color(0xFFF2800D);
  static const Color brandBrownDark = Color(0xFF1C140D);
  static const Color brandBrownLight = Color(0xFF9C7349);
  static const Color brandOffWhite = Color(0xFFFCFAF8);
  static const Color brandLightGray = Color(0xFFF4EDE7);
  final StudentUsageService _studentUsageService = StudentUsageService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initializeSelectedSchool();
  }

  Future<void> _initializeSelectedSchool() async {
    await schoolStorageService.initialize();
    if (!mounted) return;

    setState(() {
      _selectedSchool = schoolStorageService.schoolId;
      final storedName = schoolStorageService.schoolName?.trim();
      _selectedSchoolName = (storedName == null || storedName.isEmpty)
          ? 'Selected school'
          : storedName;
    });
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedSchool == null) {
      _showErrorSnackBar(
        'No school selected. Please choose your school first.',
      );
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/school-selection');
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (success) {
        // Check if user is a student
        final user = authProvider.currentUser;
        if (user?.role == UserRole.student) {
          // Validate selected school matches user's instituteId
          if (user?.instituteId == null || user!.instituteId!.isEmpty) {
            _showErrorSnackBar(
              'Your account is not linked to a school. Please contact admin.',
            );
            await authProvider.signOut();
          } else if (_selectedSchool != user.instituteId) {
            _showErrorSnackBar(
              'Your account belongs to a different school. Please change school and try again.',
            );
            await authProvider.signOut();
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/school-selection');
            }
          } else {
            // Save session
            await SessionManager.saveLoginSession(
              userId: user.uid,
              userRole: 'student',
              schoolId: user.instituteId,
            );

            // Initialize unread count provider
            if (mounted) {
              final unreadProvider = Provider.of<UnreadCountProvider>(
                context,
                listen: false,
              );
              unreadProvider.initialize(user.uid);
            }

            await _collectStudentUsageSafely(user.uid);

            if (mounted) {
              Navigator.pushReplacementNamed(context, '/student-dashboard');
            }
          }
        } else {
          _showErrorSnackBar('Access denied. This is a student-only login.');
          await authProvider.signOut();
        }
      } else {
        String errorMsg = authProvider.errorMessage ?? 'Login failed';
        // Normalize to friendly message
        errorMsg = getFriendlyErrorMessage(errorMsg);
        _showErrorSnackBar(errorMsg);
      }
    } catch (e) {
      final errorMsg = getFriendlyErrorMessage(e);
      _showErrorSnackBar(errorMsg);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    showLenvLoginError(context, message);
  }

  Future<void> _collectStudentUsageSafely(String studentId) async {
    if (!Platform.isAndroid) return;

    try {
      final hasPermission = await _studentUsageService
          .isUsagePermissionGranted();

      if (!hasPermission && mounted) {
        final shouldOpenSettings = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Enable App Usage Access'),
            content: const Text(
              'To show top used apps for parents, enable app usage access in system settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not Now'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );

        if (shouldOpenSettings == true) {
          await _studentUsageService.openUsagePermissionSettings();
        }
      }

      await _studentUsageService.collectAndSyncTodayUsage(studentId: studentId);
    } catch (_) {
      // Do not block login flow if usage tracking fails.
    }
  }

  void _handleForgotPassword() async {
    // Navigate to shared Forgot Password screen so users can edit email calmly
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ForgotPasswordScreen(role: 'student'),
      ),
    );
  }

  // Removed unused _handleSignUp method

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : brandOffWhite,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Header with Logo
              _buildHeader(),

              // Main Content (scrollable)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Welcome Text
                      _buildWelcomeText(),

                      const SizedBox(height: 40),

                      // Selected School (read-only)
                      _buildSelectedSchoolInfo(),

                      const SizedBox(height: 24),

                      // Email Field
                      _buildEmailField(),

                      const SizedBox(height: 24),

                      // Password Field
                      _buildPasswordField(),

                      const SizedBox(height: 16),

                      // Forgot Password Link
                      _buildForgotPasswordLink(),

                      const SizedBox(height: 40),

                      // Login Button
                      _buildLoginButton(),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // Footer
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 40, bottom: 20),
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFFB978), // Light orange
                Color(0xFFF2800D), // Brand orange
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: brandOrange.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CustomPaint(painter: _LogoPainter()),
        ),
      ),
    );
  }

  Widget _buildWelcomeText() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(
          'Welcome Back, Student!',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : brandBrownDark,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your credentials to access your portal.',
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.grey[400] : brandBrownLight,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSelectedSchoolInfo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2A2A2A) : brandLightGray;
    final textColor = isDark ? Colors.white : brandBrownDark;
    final subTextColor = isDark ? Colors.grey[400]! : brandBrownLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'School',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: bgColor,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.school_rounded, color: subTextColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedSchoolName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2A2A2A) : brandLightGray;
    final textColor = isDark ? Colors.white : brandBrownDark;
    final hintColor = isDark ? Colors.grey[400]! : brandBrownLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: 'you@example.com',
            hintStyle: TextStyle(color: hintColor),
            filled: true,
            fillColor: bgColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: brandOrange, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your email';
            }
            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
              return 'Please enter a valid email';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2A2A2A) : brandLightGray;
    final textColor = isDark ? Colors.white : brandBrownDark;
    final hintColor = isDark ? Colors.grey[400]! : brandBrownLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Password',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _passwordController,
          obscureText: !_isPasswordVisible,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: TextStyle(color: hintColor),
            filled: true,
            fillColor: bgColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: brandOrange, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                color: hintColor,
              ),
              onPressed: () {
                setState(() => _isPasswordVisible = !_isPasswordVisible);
              },
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your password';
            }
            if (value.length < 6) {
              return 'Password must be at least 6 characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildForgotPasswordLink() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: _handleForgotPassword,
        child: const Text(
          'Forgot Password?',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: brandOrange,
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFB978), // Light orange
            Color(0xFFF2800D), // Brand orange
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: brandOrange.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Login',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildFooter() {
    return const SizedBox.shrink();
  }
}

// Custom painter for the logo (matching HTML SVG)
class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Draw outer circle
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.35,
      paint,
    );

    // Draw inner circle (filled)
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.12,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
