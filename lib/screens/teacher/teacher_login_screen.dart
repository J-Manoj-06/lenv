import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../../services/school_service.dart';
import '../../models/school_model.dart';
import '../../utils/session_manager.dart';

class TeacherLoginScreen extends StatefulWidget {
  const TeacherLoginScreen({Key? key}) : super(key: key);

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

        // Provide user-friendly error messages
        if (errorMsg.contains('network')) {
          errorMsg =
              'Network error. Please check your internet connection and try again.';
        } else if (errorMsg.contains('user-not-found') ||
            errorMsg.contains('wrong-password')) {
          errorMsg = 'Invalid email or password';
        } else if (errorMsg.contains('too-many-requests')) {
          errorMsg = 'Too many failed attempts. Please try again later.';
        }

        _showErrorSnackBar(errorMsg);
      }
    } catch (e) {
      String errorMsg = 'Login failed: ${e.toString()}';

      if (errorMsg.contains('network')) {
        errorMsg = 'Network error. Please check your internet connection.';
      }

      _showErrorSnackBar(errorMsg);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Password reset email sent! Check your inbox.'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } else {
      _showErrorSnackBar('Failed to send reset email');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: isDarkMode ? 4 : 8,
              shadowColor: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.26),
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo and Title
                      _buildHeader(),

                      const SizedBox(height: 32),

                      // School Dropdown
                      _buildSchoolDropdown(),

                      const SizedBox(height: 16),

                      // Email Field
                      _buildEmailField(),

                      const SizedBox(height: 16),

                      // Password Field
                      _buildPasswordField(),

                      const SizedBox(height: 24),

                      // Login Button
                      _buildLoginButton(),

                      const SizedBox(height: 16),

                      // Forgot Password Link
                      _buildForgotPasswordLink(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // School Icon with Gradient
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF6366F1), // Indigo 500
                Color(0xFF4338CA), // Indigo 700
              ],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.school, color: Colors.white, size: 40),
        ),

        const SizedBox(height: 16),

        // LenV Title
        Text(
          'LenV',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.headlineLarge?.color,
          ),
        ),

        const SizedBox(height: 8),

        // Teacher Login Subtitle
        Text(
          'Teacher Login',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.titleMedium?.color,
          ),
        ),
      ],
    );
  }

  Widget _buildSchoolDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_schoolLoadError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _schoolLoadError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        DropdownButtonFormField<String>(
          value: _selectedSchool,
          dropdownColor: Theme.of(context).cardColor,
          decoration: InputDecoration(
            hintText: _isLoadingSchools
                ? 'Loading schools...'
                : 'Select your school',
            hintStyle: TextStyle(color: Theme.of(context).hintColor),
            filled: true,
            fillColor:
                Theme.of(context).inputDecorationTheme.fillColor ??
                Theme.of(context).cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_drop_down, color: Color(0xFF6366F1)),
          items: _schools
              .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
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
      ],
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        hintText: 'Email',
        hintStyle: TextStyle(color: Theme.of(context).hintColor),
        filled: true,
        fillColor:
            Theme.of(context).inputDecorationTheme.fillColor ??
            Theme.of(context).cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
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
        prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF6366F1)),
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
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: !_isPasswordVisible,
      decoration: InputDecoration(
        hintText: 'Password',
        hintStyle: TextStyle(color: Theme.of(context).hintColor),
        filled: true,
        fillColor:
            Theme.of(context).inputDecorationTheme.fillColor ??
            Theme.of(context).cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
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
        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF6366F1)),
        suffixIcon: IconButton(
          icon: Icon(
            _isPasswordVisible
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: Theme.of(context).iconTheme.color,
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
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6366F1), // Indigo 600
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: const Color(0xFF6366F1).withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Login',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  Widget _buildForgotPasswordLink() {
    return TextButton(
      onPressed: _handleForgotPassword,
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).textTheme.bodyMedium?.color,
      ),
      child: Text(
        'Forgot Password?',
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
      ),
    );
  }
}
