import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/unread_count_provider.dart';
import '../../models/user_model.dart';
import '../../services/school_service.dart';
import '../../models/school_model.dart';
import '../../utils/session_manager.dart';
import '../../utils/feedback_handler.dart';

class TeacherLoginScreen extends StatefulWidget {
  const TeacherLoginScreen({super.key});

  @override
  State<TeacherLoginScreen> createState() => _TeacherLoginScreenState();
}

class _TeacherLoginScreenState extends State<TeacherLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _selectedSchool;
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  // Teacher brand colors
  static const Color teacherPurple = Color(0xFF7E57C2);
  static const Color brandBrownDark = Color(0xFF1C140D);
  static const Color brandBrownLight = Color(0xFF9C7349);
  static const Color brandOffWhite = Color(0xFFFCFAF8);
  static const Color brandLightGray = Color(0xFFF4EDE7);

  final _schoolService = SchoolService();
  List<SchoolModel> _schools = [];
  bool _isLoadingSchools = true;
  String? _schoolLoadError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadSchools();
  }

  Future<void> _loadSchools() async {
    setState(() {
      _isLoadingSchools = true;
      _schoolLoadError = null;
    });

    try {
      final schools = await _schoolService.fetchSchools();
      if (mounted) {
        setState(() {
          _schools = schools;
          _isLoadingSchools = false;
        });

        if (schools.isEmpty) {
          setState(() {
            _schoolLoadError = 'No schools found. Please contact admin.';
          });
        }
      }
    } catch (e) {
      print('❌ Error loading schools in UI: $e');
      if (mounted) {
        setState(() {
          _isLoadingSchools = false;
          _schoolLoadError = 'Failed to load schools: $e';
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedSchool == null) {
      _showErrorSnackBar('Please select your school');
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
        // Check if user is a teacher
        final user = authProvider.currentUser;
        if (user?.role == UserRole.teacher) {
          // Validate selected school matches user's instituteId
          if (user?.instituteId == null || user!.instituteId!.isEmpty) {
            _showErrorSnackBar(
              'Your account is not linked to a school. Please contact admin.',
            );
            await authProvider.signOut();
          } else if (_selectedSchool != user.instituteId) {
            _showErrorSnackBar(
              'Selected school does not match your account\'s school.',
            );
            await authProvider.signOut();
          } else {
            // Save session
            await SessionManager.saveLoginSession(
              userId: user.uid,
              userRole: 'teacher',
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
            
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/teacher-dashboard');
            }
          }
        } else {
          _showErrorSnackBar('Access denied. This is a teacher-only login.');
          await authProvider.signOut();
        }
      } else {
        String errorMsg = authProvider.errorMessage ?? 'Login failed';
        // Normalize with friendly messages
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
    // Use universal, role-themed error snackbar
    showErrorSnackbar(context, message, role: 'teacher');
  }

  void _handleForgotPassword() async {
    if (_emailController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter your email address');
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.resetPassword(
      _emailController.text.trim(),
    );

    if (success) {
      if (mounted) {
        showSuccessSnackbar(
          context,
          'Password reset email sent! Check your inbox.',
          role: 'teacher',
        );
      }
    } else {
      _showErrorSnackBar('Failed to send reset email');
    }
  }

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

                      // School Dropdown
                      _buildSchoolDropdown(),

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
                Color(0xFFA78BFA), // Light purple
                Color(0xFF7E57C2), // Teacher purple
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: teacherPurple.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.school, color: Colors.white, size: 36),
        ),
      ),
    );
  }

  Widget _buildWelcomeText() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(
          'Welcome Back, Teacher!',
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

  Widget _buildSchoolDropdown() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2A2A2A) : brandLightGray;
    final textColor = isDark ? Colors.white : brandBrownDark;
    final hintColor = isDark ? Colors.grey[400]! : brandBrownLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select School',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        if (_schoolLoadError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _schoolLoadError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: bgColor,
          ),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedSchool,
            decoration: InputDecoration(
              hintText: _isLoadingSchools
                  ? 'Loading schools...'
                  : 'Choose your school',
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
                borderSide: const BorderSide(color: teacherPurple, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            icon: _isLoadingSchools
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(teacherPurple),
                    ),
                  )
                : Icon(Icons.keyboard_arrow_down, color: hintColor),
            dropdownColor: bgColor,
            items: _schools
                .map(
                  (s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(s.name, style: TextStyle(color: textColor)),
                  ),
                )
                .toList(),
            onChanged: _isLoadingSchools
                ? null
                : (value) {
                    setState(() => _selectedSchool = value);
                  },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please select your school';
              }
              return null;
            },
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
              borderSide: const BorderSide(color: teacherPurple, width: 2),
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
              borderSide: const BorderSide(color: teacherPurple, width: 2),
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
            color: teacherPurple,
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
            Color(0xFFA78BFA), // Light purple
            Color(0xFF7E57C2), // Teacher purple
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: teacherPurple.withOpacity(0.4),
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
